/usr/bin/sensors coretemp-isa-0000 | LC_ALL=C /usr/bin/awk '/^Core [0-9]+:/ { value=$3; gsub(/[^0-9.+-]/, "", value); sum += value; n++ } END { if (n) printf "%.1f", sum/n; else printf "100" }'
