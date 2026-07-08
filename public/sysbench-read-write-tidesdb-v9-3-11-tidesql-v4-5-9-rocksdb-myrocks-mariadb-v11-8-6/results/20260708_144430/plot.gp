set datafile separator ','
set terminal pngcairo size 1100,600 font ',11'
set grid lc rgb '#dddddd'; set border lc rgb '#666666'
set key top right; set xlabel 'time (s)'
set output 'results/20260708_144430/tps_over_time.png'
set title 'sysbench oltp\_read\_write - transactions/sec (higher is better)'
set ylabel 'transactions/sec'
plot '< grep "^rocksdb," results/20260708_144430/intervals.csv' using 2:4 with linespoints lw 2 pt 7 ps 0.7 lc rgb '#F3B802' title 'rocksdb', '< grep "^tidesdb," results/20260708_144430/intervals.csv' using 2:4 with linespoints lw 2 pt 7 ps 0.7 lc rgb '#173ACC' title 'tidesdb'
set output 'results/20260708_144430/qps_over_time.png'
set title 'sysbench oltp\_read\_write - queries/sec (higher is better)'
set ylabel 'queries/sec'
plot '< grep "^rocksdb," results/20260708_144430/intervals.csv' using 2:5 with linespoints lw 2 pt 7 ps 0.7 lc rgb '#F3B802' title 'rocksdb', '< grep "^tidesdb," results/20260708_144430/intervals.csv' using 2:5 with linespoints lw 2 pt 7 ps 0.7 lc rgb '#173ACC' title 'tidesdb'
set output 'results/20260708_144430/lat95_over_time.png'
set title 'sysbench oltp\_read\_write - p95 latency (lower is better)'
set ylabel 'p95 latency (ms)'
plot '< grep "^rocksdb," results/20260708_144430/intervals.csv' using 2:9 with linespoints lw 2 pt 7 ps 0.7 lc rgb '#F3B802' title 'rocksdb', '< grep "^tidesdb," results/20260708_144430/intervals.csv' using 2:9 with linespoints lw 2 pt 7 ps 0.7 lc rgb '#173ACC' title 'tidesdb'
set output 'results/20260708_144430/disk_over_time.png'
set title 'on-disk footprint over time (prepare dashed, run solid)'
set xlabel 'elapsed since prepare start (s)'
set ylabel 'data directory size (MB)'
set key top left
plot '< grep "^rocksdb,prepare," results/20260708_144430/disk.csv' using 3:5 with lines lw 2 dt 2 lc rgb '#F3B802' title 'rocksdb prepare', '< grep "^rocksdb,run," results/20260708_144430/disk.csv' using 3:5 with lines lw 2 lc rgb '#F3B802' title 'rocksdb run', '< grep "^tidesdb,prepare," results/20260708_144430/disk.csv' using 3:5 with lines lw 2 dt 2 lc rgb '#173ACC' title 'tidesdb prepare', '< grep "^tidesdb,run," results/20260708_144430/disk.csv' using 3:5 with lines lw 2 lc rgb '#173ACC' title 'tidesdb run'
set style fill solid 0.85 border -1
set boxwidth 0.6
unset key
set xlabel ''
set datafile separator whitespace
set output 'results/20260708_144430/prepare_time.png'
set title 'prepare time (lower is better)'
set ylabel 'prepare time (s)'
set yrange [0:*]
set xrange [-0.7:1.7]
plot 'results/20260708_144430/bars_prepare.dat' using 1:3:4:xtic(2) with boxes lc rgb variable notitle, \
     '' using 1:3:(sprintf('%.1f s',$3)) with labels offset 0,0.8 font ',10' notitle
set output 'results/20260708_144430/disk_final.png'
set title 'final on-disk footprint after run (lower is better)'
set ylabel 'data directory size (MB)'
set yrange [0:*]
set xrange [-0.7:1.7]
plot 'results/20260708_144430/bars_diskfinal.dat' using 1:3:4:xtic(2) with boxes lc rgb variable notitle, \
     '' using 1:3:(sprintf('%.0f MB',$3)) with labels offset 0,0.8 font ',10' notitle
