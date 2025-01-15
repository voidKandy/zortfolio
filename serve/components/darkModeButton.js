'use strict';

(function() {
    class DarkModeButton extends HTMLElement {
        connectedCallback() {
            const button = document.createElement("button");
            button.id = "dark-mode-button";

            this.button = button;

            if (localStorage.getItem('dark') === null) {
                localStorage.setItem('dark', this.defaultDark ? "true" : "false");
            }

            button.textContent = this.darkIsSet ? this.darkModeText : this.lightModeText;

            button.addEventListener('click', () => {
                this.toggleDarkMode();
                button.textContent = this.darkIsSet ? this.darkModeText : this.lightModeText;
            });

            this.appendChild(button);

            this.applyDarkMode();
        }

        get defaultDark() {
            return this.getAttribute('defaultDark') === 'true';
        }

        get lightModeText() {
            return this.getAttribute('lightModeText') || 'Light Mode!';
        }

        get darkModeText() {
            return this.getAttribute('darkModeText') || 'Dark Mode!';
        }

        get darkIsSet() {
            return localStorage.getItem('dark') === "true";
        }

        applyDarkMode() {
            if (this.darkIsSet) {
                document.body.classList.add("dark");
            } else {
                document.body.classList.remove("dark");
            }
        }

        toggleDarkMode() {
            if (this.darkIsSet) {
                document.body.classList.remove("dark");
                localStorage.setItem('dark', "false");
            } else {
                document.body.classList.add("dark");
                localStorage.setItem('dark', "true");
            }
        }
    }

    customElements.define('dark-mode-button', DarkModeButton);
})();

