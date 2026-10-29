/usr/bin/sensors applesmc-isa-0300 | LC_ALL=C /usr/bin/awk '$1 == "TG0H:" { value=$2; gsub(/[^0-9.+-]/, "", value); printf "%.1f", value; found=1 } END { if (!found) printf "100" }'
