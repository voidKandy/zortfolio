'use strict';

(function () {
  class SpinningShape extends HTMLElement {
    constructor() {
      super();
      this.attachShadow({ mode: 'open' });

      // Get the shape and direction attributes, with default values
      this.shape = this.getAttribute('shape') || 'pyramid'; // Default to pyramid if no attribute is provided
      this.direction = this.getAttribute('direction') || 'right'; // Default to right if no attribute is provided
    }

    connectedCallback() {
      this.shadowRoot.innerHTML = `
        <style>
          canvas {
            display: block;
            margin: 0.2rem;
            width: 100%;
            height: 100%;
          }

        </style>
        <canvas id="shape"></canvas>
      `;

      this.canvas = this.shadowRoot.querySelector("#shape");
      this.ctx = this.canvas.getContext("2d");

      // Set the canvas dimensions dynamically to be square
      this.resizeCanvas();

      // Listen for window resizing to keep the canvas responsive
      window.addEventListener("resize", () => this.resizeCanvas());

      this.angleY = 0;
      this.rotationSpeedY = 0.01;

      // Adjust rotation direction based on the `direction` attribute
      this.rotationSign = this.direction === 'left' ? -1 : 1;

      this.animate();
    }

    resizeCanvas() {
      // Set both width and height to be the same (square)
      const size = Math.min(window.innerWidth, window.innerHeight) * 0.3;  // Adjust the factor as needed
      this.canvas.width = size;
      this.canvas.height = size;
    }

    project(x, y, z) {
      const offsetX = this.canvas.width / 2;
      const offsetY = this.canvas.height / 2;

      // Calculate the scale based on the canvas size and the depth of the shape
      const maxDepth = 4; // the furthest point of the shape (constant)
      const scale = Math.min(this.canvas.width, this.canvas.height) * 0.4;  // Ensure shape fits within the canvas

      const projectedX = (x * scale) / (z + maxDepth) + offsetX;
      const projectedY = (y * scale) / (z + maxDepth) + offsetY;
      return [projectedX, projectedY];
    }

    rotateY(vertex, angle) {
      const [x, y, z] = vertex;
      return [
        x * Math.cos(angle) + z * Math.sin(angle),
        y,
        -x * Math.sin(angle) + z * Math.cos(angle),
      ];
    }

    drawCube() {
      const vertices = [
        [-1, -1, -1], [1, -1, -1], [1, 1, -1], [-1, 1, -1],  // Front face
        [-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1],     // Back face
      ];

      const edges = [
        [0, 1], [1, 2], [2, 3], [3, 0],  // Front face edges
        [4, 5], [5, 6], [6, 7], [7, 4],  // Back face edges
        [0, 4], [1, 5], [2, 6], [3, 7],  // Connecting edges
      ];

      this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

      const rotatedVertices = vertices.map(vertex => this.rotateY(vertex, this.angleY));
      const projectedVertices = rotatedVertices.map(vertex => this.project(vertex[0], vertex[1], vertex[2]));

      this.ctx.beginPath();
      edges.forEach(([start, end]) => {
        const [x1, y1] = projectedVertices[start];
        const [x2, y2] = projectedVertices[end];
        this.ctx.moveTo(x1, y1);
        this.ctx.lineTo(x2, y2);
      });
      this.ctx.strokeStyle = "#ffffff";
      this.ctx.lineWidth = 1;
      this.ctx.stroke();
    }

    drawPyramid() {
      const vertices = [
        [0, -1, 0],    // Flipped top vertex
        [-1, 1, -1],   // Flipped base vertices
        [1, 1, -1],
        [1, 1, 1],
        [-1, 1, 1],
      ];

      const edges = [
        [0, 1], [0, 2], [0, 3], [0, 4],
        [1, 2], [2, 3], [3, 4], [4, 1],
      ];

      this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);

      const rotatedVertices = vertices.map(vertex => this.rotateY(vertex, this.angleY));
      const projectedVertices = rotatedVertices.map(vertex => this.project(vertex[0], vertex[1], vertex[2]));

      this.ctx.beginPath();
      edges.forEach(([start, end]) => {
        const [x1, y1] = projectedVertices[start];
        const [x2, y2] = projectedVertices[end];
        this.ctx.moveTo(x1, y1);
        this.ctx.lineTo(x2, y2);
      });
      this.ctx.strokeStyle = "#ffffff";
      this.ctx.lineWidth = 1;
      this.ctx.stroke();
    }

    animate() {
      this.angleY += this.rotationSpeedY * this.rotationSign;
      if (this.shape === 'cube') {
        this.drawCube();
      } else {
        this.drawPyramid();
      }
      requestAnimationFrame(() => this.animate());
    }
  }

  customElements.define('spinning-shape', SpinningShape);
})();
