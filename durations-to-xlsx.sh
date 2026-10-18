#!/bin/zsh
# Write an Excel workbook with one sheet per "parent" video, listing its clips
# and their lengths in seconds.
#
# Clips are the .m2ts files in the folder, named <parent>_<NNN>.m2ts
# (e.g. martin-01_001.m2ts, martin-01_002.m2ts -> sheet "martin-01").
# Columns: Clip | Seconds, plus a total row per sheet.
# Needs only ffprobe and zip (the .xlsx is assembled by hand, no Python libs).
#
# Usage: durations-to-xlsx.sh [-o output.xlsx] [folder]
#   folder  defaults to /Volumes/td_assets/martin-family-videos/split
#   -o      output file (default: <folder>/durations.xlsx)

setopt null_glob extended_glob

out=""

while getopts "o:" opt; do
  case $opt in
    o) out=$OPTARG ;;
    *) print -u2 "Usage: ${0:t} [-o output.xlsx] [folder]"; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

dir=${1:-/Volumes/td_assets/martin-family-videos/split}
[[ -d $dir ]] || { print -u2 "Not a directory: $dir"; exit 2; }
command -v ffprobe >/dev/null || { print -u2 "ffprobe not found"; exit 1; }
command -v zip >/dev/null || { print -u2 "zip not found"; exit 1; }
dir=${dir:A}
[[ -n $out ]] || out="$dir/durations.xlsx"
out=${out:A}

files=("$dir"/*.(m2ts|M2TS)(-.N))
(( ${#files} )) || { print -u2 "No m2ts files in $dir"; exit 0; }

xml_escape() {
  local s=$1
  s=${s//&/&amp;}; s=${s//</&lt;}; s=${s//>/&gt;}; s=${s//\"/&quot;}
  print -r -- $s
}

# Group clips by parent name: strip the trailing _NNN and extension.
typeset -A group
for f in ${(o)files}; do
  parent=${${f:t:r}%_<->}
  group[$parent]+="$f"$'\n'
done

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/_rels" "$tmp/xl/_rels" "$tmp/xl/worksheets"

sheet_overrides=""
sheet_entries=""
sheet_rels=""
s=0
nclips=0
failed=0

for parent in ${(ok)group}; do
  (( s++ ))
  rows=""
  n=0
  total=0
  for f in ${(f)group[$parent]}; do
    dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" 2>/dev/null)
    (( n++ ))
    r=$((n + 1))
    name=$(xml_escape "${f:t}")
    cell_name="<c r=\"A$r\" t=\"inlineStr\"><is><t>$name</t></is></c>"
    if [[ $dur == <->(.<->)# ]]; then
      total=$(awk -v t=$total -v d=$dur 'BEGIN { printf "%.3f", t + d }')
      rows+="<row r=\"$r\">$cell_name<c r=\"B$r\" s=\"3\"><v>$dur</v></c></row>"
    else
      (( failed++ ))
      print -u2 "WARN unreadable: ${f:t}"
      rows+="<row r=\"$r\">$cell_name<c r=\"B$r\" t=\"inlineStr\"><is><t>unreadable</t></is></c></row>"
    fi
    print -u2 "$parent  ${f:t}  ${dur:-?}"
  done
  (( nclips += n ))

  last=$((n + 1))
  tr=$((n + 2))
  rows+="<row r=\"$tr\"><c r=\"A$tr\" s=\"2\" t=\"inlineStr\"><is><t>Total ($n clips)</t></is></c><c r=\"B$tr\" s=\"5\"><f>SUM(B2:B$last)</f><v>$total</v></c></row>"

  {
    print -r -- '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    print -r -- '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols><col min="1" max="1" width="40" customWidth="1"/><col min="2" max="2" width="14" customWidth="1"/></cols><sheetData>'
    print -rn -- '<row r="1"><c r="A1" s="2" t="inlineStr"><is><t>Clip</t></is></c><c r="B1" s="2" t="inlineStr"><is><t>Seconds</t></is></c></row>'
    print -rn -- "$rows"
    print -r -- '</sheetData></worksheet>'
  } > "$tmp/xl/worksheets/sheet$s.xml"

  # Sheet names: max 31 chars, none of : \ / ? * [ ]
  sname=${${parent//[\\\/\?\*\[\]:]/_}[1,31]}
  sheet_overrides+="<Override PartName=\"/xl/worksheets/sheet$s.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
  sheet_entries+="<sheet name=\"$(xml_escape "$sname")\" sheetId=\"$s\" r:id=\"rId$s\"/>"
  sheet_rels+="<Relationship Id=\"rId$s\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet$s.xml\"/>"
done

print -r -- "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>
<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>$sheet_overrides<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/></Types>" > "$tmp/[Content_Types].xml"

cat > "$tmp/_rels/.rels" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
EOF

print -r -- "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>
<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets>$sheet_entries</sheets></workbook>" > "$tmp/xl/workbook.xml"

print -r -- "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>
<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">$sheet_rels<Relationship Id=\"rId$((s + 1))\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>" > "$tmp/xl/_rels/workbook.xml.rels"

# Styles: 0 default, 2 bold, 3 0.00 seconds, 5 bold 0.00
cat > "$tmp/xl/styles.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="6"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="46" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="2" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="46" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/><xf numFmtId="2" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/></cellXfs></styleSheet>
EOF

rm -f "$out"
( cd "$tmp" && zip -X -q -r "$out" '[Content_Types].xml' _rels xl ) || { print -u2 "zip failed"; exit 1; }

print -u2 "Wrote $out ($s sheets, $nclips clips, $failed unreadable)"
