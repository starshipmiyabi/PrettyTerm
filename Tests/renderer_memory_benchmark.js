(async () => {
  const messages = Array.from({ length: 300 }, (_, i) => [
    { role: 'user', text: `Question ${i}` },
    { role: 'assistant', messageKey: `bench-${i}`,
      text: Array.from({ length: 12 }, (_, j) =>
        `Paragraph ${i}-${j}: $\\frac{x_${j}^2 + y^2}{\\sqrt{1+z^2}}$`).join('\n\n') }
  ]).flat();
  const start = performance.now();
  await setClaudeSession({ sessionId: 'memory-benchmark', messages });
  window.__ptBenchmarkResult = {
    turns: document.querySelectorAll('section.turn').length,
    totalFormulas: 3600,
    residentFormulas: document.querySelectorAll('mjx-container').length,
    domElements: document.querySelectorAll('*').length,
    renderMilliseconds: Math.round(performance.now() - start)
  };
})();
