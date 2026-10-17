#!/bin/zsh
# Write an Excel spreadsheet listing each mp4 in a folder and its duration.
#
# Columns: File | Duration (h:mm:ss) | Seconds, plus a total row.
# Needs only ffprobe and zip (the .xlsx is assembled by hand, no Python libs).
#
# Usage: durations-to-xlsx.sh [-o output.xlsx] [-r] <folder>
#   -o  output file (default: <folder>/durations.xlsx)
#   -r  recurse into subfolders (file column shows the relative path)

setopt null_glob extended_glob

out=""
recurse=0

while getopts "o:r" opt; do
  case $opt in
    o) out=$OPTARG ;;
    r) recurse=1 ;;
    *) print -u2 "Usage: ${0:t} [-o output.xlsx] [-r] <folder>"; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

dir=${1:-.}
[[ -d $dir ]] || { print -u2 "Not a directory: $dir"; exit 2; }
command -v ffprobe >/dev/null || { print -u2 "ffprobe not found"; exit 1; }
command -v zip >/dev/null || { print -u2 "zip not found"; exit 1; }
dir=${dir:A}
[[ -n $out ]] || out="$dir/durations.xlsx"
out=${out:A}

if (( recurse )); then
  files=("$dir"/**/*.(mp4|MP4)(.N))
else
  files=("$dir"/*.(mp4|MP4)(.N))
fi
(( ${#files} )) || { print -u2 "No mp4 files in $dir"; exit 0; }

xml_escape() {
  local s=$1
  s=${s//&/&amp;}; s=${s//</&lt;}; s=${s//>/&gt;}; s=${s//\"/&quot;}
  print -r -- $s
}

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/_rels" "$tmp/xl/_rels" "$tmp/xl/worksheets"

rows=""
n=0
total=0
failed=0
for f in ${(o)files}; do
  rel=${f#$dir/}
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" 2>/dev/null)
  (( n++ ))
  r=$((n + 1))
  name=$(xml_escape "$rel")
  cell_name="<c r=\"A$r\" t=\"inlineStr\"><is><t>$name</t></is></c>"
  if [[ $dur == <->(.<->)# ]]; then
    total=$(awk -v t=$total -v d=$dur 'BEGIN { printf "%.3f", t + d }')
    rows+="<row r=\"$r\">$cell_name<c r=\"B$r\" s=\"1\"><f>C$r/86400</f><v>$(awk -v d=$dur 'BEGIN { printf "%.10f", d / 86400 }')</v></c><c r=\"C$r\" s=\"3\"><v>$dur</v></c></row>"
  else
    (( failed++ ))
    print -u2 "WARN unreadable: $rel"
    rows+="<row r=\"$r\">$cell_name<c r=\"B$r\" t=\"inlineStr\"><is><t>unreadable</t></is></c></row>"
  fi
  print -u2 "$rel  ${dur:-?}"
done

last=$((n + 1))
tr=$((n + 2))
rows+="<row r=\"$tr\"><c r=\"A$tr\" s=\"2\" t=\"inlineStr\"><is><t>Total ($n files)</t></is></c><c r=\"B$tr\" s=\"4\"><f>SUM(B2:B$last)</f><v>$(awk -v d=$total 'BEGIN { printf "%.10f", d / 86400 }')</v></c><c r=\"C$tr\" s=\"5\"><f>SUM(C2:C$last)</f><v>$total</v></c></row>"

cat > "$tmp/[Content_Types].xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>
EOF

cat > "$tmp/_rels/.rels" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
EOF

cat > "$tmp/xl/workbook.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Durations" sheetId="1" r:id="rId1"/></sheets></workbook>
EOF

cat > "$tmp/xl/_rels/workbook.xml.rels" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
EOF

# Styles: 0 default, 1 [h]:mm:ss, 2 bold, 3 0.00 seconds, 4 bold [h]:mm:ss, 5 bold 0.00
cat > "$tmp/xl/styles.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="6"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="46" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="2" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="46" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/><xf numFmtId="2" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/></cellXfs></styleSheet>
EOF

{
  print -r -- '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
  print -r -- '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols><col min="1" max="1" width="60" customWidth="1"/><col min="2" max="2" width="18" customWidth="1"/><col min="3" max="3" width="12" customWidth="1"/></cols><sheetData>'
  print -rn -- '<row r="1"><c r="A1" s="2" t="inlineStr"><is><t>File</t></is></c><c r="B1" s="2" t="inlineStr"><is><t>Duration (h:mm:ss)</t></is></c><c r="C1" s="2" t="inlineStr"><is><t>Seconds</t></is></c></row>'
  print -rn -- "$rows"
  print -r -- '</sheetData></worksheet>'
} > "$tmp/xl/worksheets/sheet1.xml"

rm -f "$out"
( cd "$tmp" && zip -X -q -r "$out" '[Content_Types].xml' _rels xl ) || { print -u2 "zip failed"; exit 1; }

print -u2 "Wrote $out ($n files, $failed unreadable)"
