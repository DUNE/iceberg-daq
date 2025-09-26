# Align DAPHNE-V3 End point
#
dtsbutler mst BOREAS_TLU_ICEBERG align apply-delay 0x0020 0 0 --force
sleep 5
#
dtsbutler mst BOREAS_TLU_ICEBERG align toggle-tx 0x0020  --on > /dev/null
sleep 5
dtsbutler mst BOREAS_TLU_ICEBERG align toggle-tx 0x0020 --off > /dev/null
sleep 5
#
dtsbutler mst  BOREAS_TLU_ICEBERG align toggle-tx 0x0FFF
