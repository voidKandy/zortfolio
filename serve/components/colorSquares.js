'use strict';

(function() {
    class ColorSquares extends HTMLElement {
        connectedCallback() {

            // Create a container for the colors
            const container = document.createElement('div');
            container.id = 'color-row';

            const root = document.documentElement;
            const rootStyles = getComputedStyle(root);
            const cssVariables = [];

            // Loop through all styles and filter for CSS variables
            for (let i = 0; i < rootStyles.length; i++) {
                const property = rootStyles[i];
                if (property.startsWith('--')) {
                    cssVariables.push(property);
                }
            }

            // Append squares for each CSS variable
            cssVariables.filter(v => {
                // We only want hexadecimal colors
                return rootStyles.getPropertyValue(v).trim().charAt(0) == '#';
            }).forEach(variable => {
                const colorValue = rootStyles.getPropertyValue(variable).trim();

                const square = document.createElement('div');
                square.style.backgroundColor = colorValue;
                square.classList.add("square");


                square.addEventListener('click', () => {
                    navigator.clipboard.writeText(colorValue)
                        .catch(err => {
                            console.error('Failed to copy text: ', err);
                        });
                });

                const squareContainer = document.createElement('div');
                squareContainer.classList.add("square-container");
                squareContainer.appendChild(square);
                container.appendChild(squareContainer);
            });

            // Create styles for shadow DOM
            const style = document.createElement("style");
            style.textContent = `
                #color-row {
                    display: flex;
                    flex-grow: 1;
                    flex-direction: row;
                    height: 100%;
                }
                .square {
                    height: 100%;
                    flex: 1 1 auto;
                    margin: 0.5rem;
                    cursor: url("dropper.cur"), auto;
                }
                .square-container {
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    width: 80%; 
                }
            `;

            // Attach shadow DOM and append the container and styles
            this.attachShadow({ mode: 'open' }).appendChild(style);
            this.shadowRoot.appendChild(container);
        }
    }

    customElements.define('color-squares', ColorSquares);
})();
