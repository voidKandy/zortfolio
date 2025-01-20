
'use strict';

(function() {

  // Define the custom web component for the spinning cube
class SpinningCube extends HTMLElement {
  constructor() {
    super();
    // Attach shadow DOM to encapsulate styles and markup
    this.attachShadow({ mode: 'open' });
  }

  connectedCallback() {
    // Create and append the HTML structure for the web component
    this.shadowRoot.innerHTML = `
      <style>
        canvas {
          display: block;
          margin: 0 auto;
        }
        .controls {
          text-align: center;
          margin-top: 20px;
        }
        .slider {
          width: 100%;
        }
      </style>
      <div class="controls">
        <label>Rotation Speed (X): <span id="speedXValue">0.02</span></label><br>
        <input type="range" id="speedX" class="slider" min="0" max="0.1" step="0.001" value="0.02"><br>
        
        <label>Rotation Speed (Y): <span id="speedYValue">0.02</span></label><br>
        <input type="range" id="speedY" class="slider" min="0" max="0.1" step="0.001" value="0.02"><br>
        
        <label>Wireframe Color:</label><br>
        <input type="color" id="colorPicker" value="#ffffff">
      </div>
      <canvas id="plasma"></canvas>
    `;

    this.canvas = this.shadowRoot.querySelector("#plasma");
    this.ctx = this.canvas.getContext("2d");

    // Set canvas size
    this.canvas.width = 500;
    this.canvas.height = 500;

    // Get controls
    this.speedXSlider = this.shadowRoot.querySelector("#speedX");
    this.speedYSlider = this.shadowRoot.querySelector("#speedY");
    this.colorPicker = this.shadowRoot.querySelector("#colorPicker");

    // Set initial rotation speed and color
    this.angleX = 0;
    this.angleY = 0;
    this.rotationSpeedX = 0.02;
    this.rotationSpeedY = 0.02;
    this.color = "#ffffff";

    // Set up the event listeners for the controls
    this.speedXSlider.addEventListener("input", (e) => {
      this.rotationSpeedX = parseFloat(e.target.value);
      this.shadowRoot.querySelector("#speedXValue").textContent = e.target.value;
    });

    this.speedYSlider.addEventListener("input", (e) => {
      this.rotationSpeedY = parseFloat(e.target.value);
      this.shadowRoot.querySelector("#speedYValue").textContent = e.target.value;
    });

    this.colorPicker.addEventListener("input", (e) => {
      this.color = e.target.value;
    });

    // Start the animation loop
    this.animate();
  }

  // Cube logic
  project(x, y, z) {
    const scale = 300;
    const offsetX = this.canvas.width / 2;
    const offsetY = this.canvas.height / 2;
    const projectedX = x * scale / (z + 4) + offsetX;
    const projectedY = y * scale / (z + 4) + offsetY;
    return [projectedX, projectedY];
  }

  rotateX(vertex, angle) {
    const [x, y, z] = vertex;
    return [
      x,
      y * Math.cos(angle) - z * Math.sin(angle),
      y * Math.sin(angle) + z * Math.cos(angle)
    ];
  }

  rotateY(vertex, angle) {
    const [x, y, z] = vertex;
    return [
      x * Math.cos(angle) + z * Math.sin(angle),
      y,
      -x * Math.sin(angle) + z * Math.cos(angle)
    ];
  }

  drawCube() {
    const vertices = [
      [-1, -1, -1], [ 1, -1, -1], [ 1,  1, -1], [-1,  1, -1],
      [-1, -1,  1], [ 1, -1,  1], [ 1,  1,  1], [-1,  1,  1]
    ];

    const edges = [
      [0, 1], [1, 2], [2, 3], [3, 0],
      [4, 5], [5, 6], [6, 7], [7, 4],
      [0, 4], [1, 5], [2, 6], [3, 7]
    ];

    this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

    const rotatedVertices = vertices.map(vertex => {
      let rotated = this.rotateX(vertex, this.angleX);
      rotated = this.rotateY(rotated, this.angleY);
      return rotated;
    });

    const projectedVertices = rotatedVertices.map(vertex =>
      this.project(vertex[0], vertex[1], vertex[2])
    );

    this.ctx.beginPath();
    edges.forEach(([start, end]) => {
      const [x1, y1] = projectedVertices[start];
      const [x2, y2] = projectedVertices[end];
      this.ctx.moveTo(x1, y1);
      this.ctx.lineTo(x2, y2);
    });
    this.ctx.strokeStyle = this.color;
    this.ctx.lineWidth = 1;
    this.ctx.stroke();
  }

  animate() {
    this.angleX += this.rotationSpeedX;
    this.angleY += this.rotationSpeedY;
    this.drawCube();
    requestAnimationFrame(() => this.animate());
  }
}

// Define the custom element
customElements.define('spinning-cube', SpinningCube);



})();
