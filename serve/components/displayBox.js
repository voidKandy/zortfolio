'use strict';

(function() {
    class DisplayBox extends HTMLElement {
        connectedCallback() {
            const container = document.createElement("div");
            container.classList.add('container');

            const title = document.createElement("h2");
            title.textContent = this.title; 
            title.classList.add("display-box-title");

            container.appendChild(title);

            Array.from(this.children).forEach(child => {
                child.style.margin = "1rem"; 
                child.style.width = "90%"; 
                container.appendChild(child);
            });

            const style = document.createElement("style");
            style.textContent = `
                .container {
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    border-style: solid;
                    border-width: 2.5px;
                    border-color: light-dark(var(--light-border), var(--dark-border));
                    background-color: light-dark(var(--offwhite), var(--offblack));
                    padding: 0rem 2rem 2rem  rem;
                    margin: 2rem;
                    box-shadow: 1px 3px 3px light-dark(rgba(0, 0, 0, 0.4), rgba(200, 200, 200, 0.4));
                    transition: all ease-in-out 200ms;
                    filter: saturate(150%);
                }
                .container > :nth-child(2) {
                    margin-bottom: 0;
                }
                .container > :last-child {
                    margin-top: 0;
                }
                .container > *:not(:first-child) {
                    transition: transform 200ms ease-in, transform 400ms ease-out;
                }
                .container > *:not(:first-child):hover {
                    transform: scale(1.005);
                }
                .container > *:not(:first-child):not(:last-child) {
                    border-bottom: 2px dotted light-dark(var(--light-border), var(--dark-border));
                    padding-bottom: 1rem; 
                }
                .container:hover {
                    box-shadow: 2px 4px 2px light-dark(rgba(0, 0, 0, 0.5), rgba(200, 200, 200, 0.5));
                }
                .container:hover > .display-box-title {
                    filter: saturate(110%);
                }
                .display-box-title {
                    text-align: center;
                    padding: 1rem 0rem;
                    width: 100%;
                    border-bottom: 2px solid light-dark(var(--light-border), var(--dark-border));
                    background-color: var(--primary-orange);
                    font-size: 1.5rem;
                    font-weight: bold;
                    color: var(--light-color);
                    margin:  0;
                    transition: all ease-in-out 200ms;
                }
            `;
            // Attach the container to the shadow DOM
            this.attachShadow({ mode: 'open' }).appendChild(style);
            this.shadowRoot.appendChild(container);
        }

        get title() {
            return this.getAttribute("title");
        }
    }

    customElements.define('display-box', DisplayBox);
})();
