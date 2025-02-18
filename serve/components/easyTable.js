'use strict';

(function() {
    class EasyTable extends HTMLElement {
            connectedCallback() {
                const table = document.createElement("table");
                const topRow = document.createElement("tr");
                const topHeader = document.createElement("th");
                topHeader.colSpan = 2;
                topHeader.textContent = this.header;

                topRow.appendChild(topHeader);
                table.appendChild(topRow);

               Array.from(this.attributes).forEach(attr => {
                    if (attr.name.startsWith("row-")) {
                        const rowLabel = attr.name.replace("row-", "").replaceAll("-", " ");
                        const rowValues = this.getAttributeValues(attr.name);
                        if (rowValues) {
                            table.appendChild(this.buildTableRow(rowLabel, rowValues));
                        }
                    }
                });

                
                const style = document.createElement("style");
                     style.textContent = `
                     table {
                        border-collapse: collapse;
                        border: 5px inset light-dark(var(--light-border), var(--dark-border));
                        background-color: light-dark(var(--offwhite), var(--offblack));
                        margin: 0 auto; /* Center the table */
                        width: auto;
                     }
                     table tr:first-child th {
                        font-size: 1.5rem;
                        padding: 0.5rem;
                        background-color: light-dark(var(--tertiary-blue), var(--secondary-red));
                        filter: grayscale(10%);
                        color: light-dark(var(--light-color), var(--dark-color));
                     }

                     table td {
                         padding: 1rem;
                     }

                     table tr {
                        border-bottom: 1px solid light-dark(var(--light-border), var(--dark-border));
                     }

                     table tr:not(:first-child) td:first-child {
                         vertical-align: top;
                         font-size: 1.2rem;
                         font-weight: 900;
                         color: light-dark(var(--light-color), var(--dark-color));
                     }

                     table tr:not(:first-child) td:last-child {
                         text-align: right;
                         gap: 1rem;
                     }

                     h4.has-link {
                         transition: all ease-in-out 100ms;
                     }

                     h4.has-link:hover {
                        color: light-dark(var(--tertiary-blue), var(--secondary-red));
                     }

                     h4 {
                        text-decoration: underline;
                        color: light-dark(var(--secondary-red), var(--tertiary-blue));
                     }
                `;
            


                this.attachShadow({ mode: 'open' }).appendChild(style);
                this.shadowRoot.appendChild(table);
                
            }

            get header() {
                let header = this.getAttribute("header");
                if (!header) {
                    console.log("make sure to pass a header attribute");
                }
                return header;
                
            }

            /**
             * @param {string} rowName
             * @param {Array<{value: string, link: string}>} vals 
             * @returns {HTMLTableRowElement}
             */
            buildTableRow(rowName, vals) {
                    const row = document.createElement("tr");
                    const leftCell = document.createElement("td");
                    leftCell.textContent = rowName;
                    const rightCell = document.createElement("td");
                    vals.forEach(({value, link}) => {
                        const tableName = document.createElement("h4");
                        tableName.textContent = value;
                        if (link) {
                            const tableLink = document.createElement("a");
                            tableLink.href = link;
                            tableLink.target = "_blank";
                            tableLink.style.textDecoration = "none";
                            tableLink.appendChild(tableName);
                            tableName.classList.add("has-link");
                            rightCell.appendChild(tableLink);
                        } else {
                            rightCell.appendChild(tableName);
                        }
                    });
                    row.appendChild(leftCell);
                    row.appendChild(rightCell);
                    return row;
                    
            }

            /**
             * @param {string} name - attribute name
             * @returns {Array<{value: string, link: string | null}> | null} - A *possible* list of values to be put into the table associated with the attribute
             */
            getAttributeValues(name) {
                let content =  this.getAttribute(name);
                if (content == null) {
                    return null;
                }
                return content.split(",").map((val) => this.parseInput(val.trim()));
            }

            /**
             * Parses an input string of the format <table value>:<link>
             * If ':' is omitted before whitespace, the value is assumed to have no link.
             * Links are automatically prefixed with "https://".
             * Attrbributes should *split* their input text on commas before passing the slices to this function
             * Any "-" present in the name of the item (the string slice **before** the ':') will be changed to a space
             * 
             * @param {string} str - input string, should be a single line
             * @returns {{ value: string, link: string | null }} - Parsed value and optional link
             */
            parseInput(str) {
                const match = str.match(/^([^:\s]+)(?::\s*(\S+))?$/);
                if (match) {
                    let value = match[1].trim().replaceAll("-", " ");
                    let link = match[2] ? `https://${match[2].trim()}` : null;
                    return { value, link };
                }
                return { value: str.trim(), link: null };
            }

        }
        customElements.define('easy-table', EasyTable);
})();
