

'use strict';

(function() {
    class WorkItem extends HTMLElement {
        connectedCallback() {
            const container = document.createElement("div");

            const companyName = document.createElement("h3");
            companyName.textContent = this.company;

            if (this.link) {
                const companyLink = document.createElement("a");
                companyLink.href = this.link;
                companyLink.target = "_blank";
                companyLink.style.textDecoration = "none";
                companyLink.appendChild(companyName);
                companyName.classList.add("has-link");
                container.appendChild(companyLink);
            } else {
                container.appendChild(companyName);
            }

            const position = document.createElement("h4");
            position.textContent = this.position;
            container.appendChild(position);

            const startEnd = document.createElement("h4");
            startEnd.textContent = `(${this.startDate} - ${this.endDate})`
            container.appendChild(startEnd);

            const description = document.createElement("p");
            description.textContent = this.description;
            container.appendChild(description);

            const style = document.createElement("style");
                 style.textContent = `
                h3.has-link {
                  transition: all ease-in-out 100ms;
                }
                h3.has-link:hover {
                    color: var(--tertiary-blue);
                }
                h3{
                    color: var(--secondary-red);
                    display: inline-block;
                }
                h4 {
                    color: var(--tertiary-blue);
                }
                p {
                    font-size: 1rem;
                    color: light-dark(var(--light-color), var(--dark-color));
                }
            `;
            
            this.attachShadow({ mode: 'open' }).appendChild(style);
            this.shadowRoot.appendChild(container);
        }

        get company() {
          const company = this.getAttribute("company");
          if (company == null) {
            console.log("you should pass a company attribute");
          }
          return company;
        }
        get link() {
          return this.getAttribute("link");
        }
        get position() {
          const position = this.getAttribute("position");
          if (position == null) {
            console.log("you should pass a position attribute");
          }
          return position;
        }
        get startDate() {
          const startDate = this.getAttribute("startDate");
          if (startDate == null) {
            console.log("you should pass a startDate attribute");
          }
          return startDate;
        }
        get endDate() {
          return this.getAttribute("endDate") || "Present";
        }
        get description() {
          const description = this.getAttribute("description");
          if (description == null) {
            console.log("you should pass a description attribute");
          }
          return description;
        }
    }

    customElements.define('work-item', WorkItem);
})();
