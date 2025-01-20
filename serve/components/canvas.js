document.addEventListener("DOMContentLoaded", () => {
   const canvas = document.getElementById("plasma");
   const ctx = canvas.getContext("2d");

   const width = canvas.width;
   const height = canvas.height;

   // Cube vertices (in 3D space)
   const vertices = [
      [-1, -1, -1], [ 1, -1, -1], [ 1,  1, -1], [-1,  1, -1],  // Front
      [-1, -1,  1], [ 1, -1,  1], [ 1,  1,  1], [-1,  1,  1]   // Back
   ];

   // Cube edges (connecting indices of the vertices array)
   const edges = [
      [0, 1], [1, 2], [2, 3], [3, 0],  // Front face
      [4, 5], [5, 6], [6, 7], [7, 4],  // Back face
      [0, 4], [1, 5], [2, 6], [3, 7]   // Connecting front and back
   ];

   // Set up the cube's initial position, size, and rotation speed
   let angleX = 0;
   let angleY = 0;

   // Projection function (simple perspective projection)
   function project(x, y, z) {
      const scale = 300; // How far the object is from the viewer
      const offsetX = width / 2;
      const offsetY = height / 2;

      const projectedX = x * scale / (z + 4) + offsetX;
      const projectedY = y * scale / (z + 4) + offsetY;
      return [projectedX, projectedY];
   }

   // Rotation functions (around X and Y axes)
   function rotateX(vertex, angle) {
      const [x, y, z] = vertex;
      return [
         x,
         y * Math.cos(angle) - z * Math.sin(angle),
         y * Math.sin(angle) + z * Math.cos(angle)
      ];
   }

   function rotateY(vertex, angle) {
      const [x, y, z] = vertex;
      return [
         x * Math.cos(angle) + z * Math.sin(angle),
         y,
         -x * Math.sin(angle) + z * Math.cos(angle)
      ];
   }

   // Draw the cube
   function drawCube() {
      ctx.clearRect(0, 0, width, height); // Clear the canvas

      // Rotate each vertex
      const rotatedVertices = vertices.map(vertex => {
         let rotated = rotateX(vertex, angleX);
         rotated = rotateY(rotated, angleY);
         return rotated;
      });

      // Project each vertex to 2D
      const projectedVertices = rotatedVertices.map(vertex => project(vertex[0], vertex[1], vertex[2]));

      // Draw the edges
      ctx.beginPath();
      edges.forEach(([start, end]) => {
         const [x1, y1] = projectedVertices[start];
         const [x2, y2] = projectedVertices[end];
         ctx.moveTo(x1, y1);
         ctx.lineTo(x2, y2);
      });
      ctx.strokeStyle = "white";
      ctx.lineWidth = 1;
      ctx.stroke();
   }

   // Animation loop
   function animate() {
      angleX += 0.02; // Rotation speed around X-axis
      angleY += 0.02; // Rotation speed around Y-axis

      drawCube(); // Draw the updated cube
      requestAnimationFrame(animate); // Loop the animation
   }

   // Start the animation
   animate();
});
