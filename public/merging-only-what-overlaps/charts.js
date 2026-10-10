document.addEventListener('DOMContentLoaded', function () {
  const ink = '#8792a2';
  const grid = 'rgba(135, 146, 162, 0.2)';
  const t = [0, 3, 6, 10, 15, 18, 21, 25, 29, 32, 35, 38, 42, 45, 48, 51, 54, 57, 58, 59, 60, 64, 70, 75];
  const levels = [
    ['L1', '#b4dbf7', [0, 13, 5, 37, 16, 8, 16, 5, 16, 8, 0, 0, 0, 4, 2, 4, 4, 0, 0, 0, 0, 0, 0, 0]],
    ['L2', '#809ae0', [0, 0, 0, 0, 29, 7, 2, 13, 4, 12, 13, 0, 0, 8, 5, 5, 8, 4, 0, 0, 0, 0, 0, 0]],
    ['L3', '#193EDC', [0, 118, 215, 272, 398, 27, 45, 37, 48, 28, 68, 0, 0, 13, 36, 48, 59, 72, 75, 40, 0, 0, 0, 0]],
    ['L4', '#0a2540', [0, 0, 0, 0, 0, 445, 558, 699, 864, 960, 986, 1067, 1067, 1067, 1067, 1067, 1067, 1067, 1055, 616, 111, 111, 109, 107]]
  ];
  new Chart(document.getElementById('cmp-levels'), {
    type: 'line',
    data: {
      labels: t,
      datasets: levels.map(([label, color, data]) => ({
        label, data, borderColor: color, backgroundColor: color + 'cc', fill: true, pointRadius: 0, tension: 0.2
      }))
    },
    options: {
      responsive: true,
      aspectRatio: 2.2,
      plugins: {
        legend: { labels: { color: ink, boxWidth: 12 } },
        title: { display: true, text: 'MB in each level over time, loading then deleting nine in ten', color: ink, font: { size: 13, weight: 'normal' } }
      },
      scales: {
        x: { type: 'linear', title: { display: true, text: 'seconds', color: ink }, ticks: { color: ink }, grid: { color: grid } },
        y: { stacked: true, beginAtZero: true, ticks: { color: ink }, grid: { color: grid } }
      }
    }
  });

  const valueLabels = {
    id: 'valueLabels',
    afterDatasetsDraw(chart, args, opts) {
      const ctx = chart.ctx;
      ctx.save();
      ctx.fillStyle = ink;
      ctx.font = '11px system-ui, sans-serif';
      ctx.textAlign = 'center';
      chart.getDatasetMeta(0).data.forEach((bar, i) => ctx.fillText(opts.labels[i], bar.x, bar.y - 5));
      ctx.restore();
    }
  };
  const offsets = ['offset 0', 'offset 1', 'offset 2'];
  const colors = ['#809ae0', '#193EDC', '#b4dbf7'];
  const panels = [
    ['cmp-load', 'load seconds by dividing level', offsets, [29.6, 29.0, 41.6], ['29.6', '29.0', '41.6'], colors],
    ['cmp-merges', 'merges during the load', offsets, [806, 613, 96], ['806', '613', '96'], colors],
    ['cmp-largest', 'largest single merge, MB', offsets, [107, 424, 1026], ['107', '424', '1,026'], colors],
    ['cmp-readamp', 'read amplification once settled', offsets, [2, 2, 3], ['2', '2', '3'], colors],
    ['cmp-threads', 'load seconds by compaction threads', ['1 thread', '2 threads', '4 threads'], [59.4, 29.0, 23.1], ['59.4', '29.0', '23.1'], ['#b4dbf7', '#193EDC', '#0a2540']],
    ['cmp-order-wa', 'write amplification by key order', ['random', 'sequential'], [11.13, 4.18], ['11.1', '4.2'], ['#809ae0', '#193EDC']],
    ['cmp-order-written', 'GB compaction wrote', ['random', 'sequential'], [10.68, 3.36], ['10.7', '3.4'], ['#809ae0', '#193EDC']],
    ['cmp-order-load', 'load seconds by key order', ['random', 'sequential'], [36.0, 15.6], ['36.0', '15.6'], ['#809ae0', '#193EDC']]
  ];
  for (const [id, title, labels, data, text, palette] of panels) {
    new Chart(document.getElementById(id), {
      type: 'bar',
      data: { labels, datasets: [{ data, backgroundColor: palette, borderRadius: 3 }] },
      options: {
        responsive: true,
        aspectRatio: 1.2,
        layout: { padding: { top: 18 } },
        plugins: {
          legend: { display: false },
          title: { display: true, text: title, color: ink, font: { size: 13, weight: 'normal' } },
          valueLabels: { labels: text }
        },
        scales: {
          x: { ticks: { color: ink, font: { size: 10 } }, grid: { display: false } },
          y: { beginAtZero: true, grace: '18%', ticks: { color: ink, font: { size: 10 }, maxTicksLimit: 5 }, grid: { color: grid } }
        }
      },
      plugins: [valueLabels]
    });
  }
});
