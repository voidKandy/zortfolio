
'use strict';

(function() {
    /**
    * This is for rendering any projects.
    * Children of this element will be rendered in a row underneath the project name
    * currently, it is advisable to only use small images or text as children
    **/
    class ProjectItem extends HTMLElement {
        connectedCallback() {
            const container = document.createElement("div");

            const titleLink = document.createElement("a");
            titleLink.href = this.link;
            titleLink.target = "_blank";
            titleLink.style.textDecoration = "none"; 

            const title = document.createElement("h3");
            title.textContent = this.name; 

            titleLink.appendChild(title);
            container.appendChild(titleLink);

            if (this.children.length > 0) {

              const childrenContainer = document.createElement("div");
              childrenContainer.classList.add('child-container');
              Array.from(this.children).forEach(child => {
                  childrenContainer.appendChild(child);
              });
              container.appendChild(childrenContainer);

            }


            const description = document.createElement("p");
            description.textContent = this.description;
            container.appendChild(description);



            const style = document.createElement("style");
                 style.textContent = `
                 .child-container {
                     display: flex;
                     flex-direction: row;
                     align-items: center;
                     justify-content: flex-start;
                     gap: 0.5rem;
                }
                h3 {
                    display: inline-block;
                    font-size: 1.5rem;
                    margin: 0.5rem 0;
                    color: var(--secondary-red);
                    transition: all ease-in-out 100ms;
                }
                h3:hover {
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

        get name() {
          const name = this.getAttribute("name");
          if (name == null) {
            console.log("you should pass a name attribute");
          }
          return name;
        }
        get description() {
          const description = this.getAttribute("description");
          if (description == null) {
            console.log("you should pass a description attribute");
          }
          return description;
        }
        get link() {
          const link = this.getAttribute("link");
          if (link == null) {
            console.log("you should pass a link attribute");
          }
          return link;
        }
    }

    customElements.define('project-item', ProjectItem);
})();
