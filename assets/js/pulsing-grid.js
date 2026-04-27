// Pulsing Grid Animation for CUDA execution model visualization
// Represents parallel thread execution in SIMT architecture

(function() {
  document.addEventListener('DOMContentLoaded', function() {
    const canvas = document.getElementById('cuda-pulsing-grid');
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    const width = canvas.width;
    const height = canvas.height;
    const centerX = width / 2;
    const centerY = height / 2;
    const gridSize = 5;
    const spacing = 22;
    const breathingSpeed = 0.5;
    const waveSpeed = 1.2;
    const colorPulseSpeed = 1.0;
    let time = 0;

    function draw() {
      ctx.clearRect(0, 0, width, height);

      // Breathing effect - grid expands and contracts
      const breathingFactor = Math.sin(time * breathingSpeed) * 0.15 + 1.0;
      const currentSpacing = spacing * breathingFactor;
      const startX = centerX - (currentSpacing * (gridSize - 1)) / 2;
      const startY = centerY - (currentSpacing * (gridSize - 1)) / 2;
      const dots = [];

      // Calculate dot positions and properties
      for (let row = 0; row < gridSize; row++) {
        for (let col = 0; col < gridSize; col++) {
          const x = startX + col * currentSpacing;
          const y = startY + row * currentSpacing;
          const distFromCenter = Math.sqrt(Math.pow(col - 2, 2) + Math.pow(row - 2, 2));

          // Radial wave from center
          const radialWave = Math.sin(time * waveSpeed - distFromCenter * 0.8) * 0.5 + 0.5;

          // Spiral wave overlay
          const angle = Math.atan2(row - 2, col - 2);
          const spiralWave = Math.sin(time * 0.8 + angle * 2 + distFromCenter) * 0.3 + 0.7;

          // Color pulsing - white to light blue
          const colorPhase = Math.sin(time * colorPulseSpeed + distFromCenter * 0.5);
          const r = Math.floor(200 + colorPhase * 55);
          const g = Math.floor(220 + colorPhase * 35);
          const b = 255;

          const baseSize = 3;
          const size = baseSize * (0.6 + radialWave * 0.6) * spiralWave;

          dots.push({ x, y, r, g, b, size, radialWave });
        }
      }

      // Draw connecting lines (network effect)
      ctx.lineWidth = 0.5;
      for (let i = 0; i < dots.length; i++) {
        for (let j = i + 1; j < dots.length; j++) {
          const dist = Math.sqrt(
            Math.pow(dots[i].x - dots[j].x, 2) +
            Math.pow(dots[i].y - dots[j].y, 2)
          );
          if (dist < currentSpacing * 1.5) {
            const alpha = (1 - dist / (currentSpacing * 1.5)) * 0.3 *
                         ((dots[i].radialWave + dots[j].radialWave) / 2);
            ctx.strokeStyle = `rgba(100, 150, 200, ${alpha})`;
            ctx.beginPath();
            ctx.moveTo(dots[i].x, dots[i].y);
            ctx.lineTo(dots[j].x, dots[j].y);
            ctx.stroke();
          }
        }
      }

      // Draw dots
      for (const dot of dots) {
        ctx.fillStyle = `rgb(${dot.r}, ${dot.g}, ${dot.b})`;
        ctx.beginPath();
        ctx.arc(dot.x, dot.y, dot.size, 0, Math.PI * 2);
        ctx.fill();
      }

      time += 0.016;
      requestAnimationFrame(draw);
    }

    draw();
  });
})();
