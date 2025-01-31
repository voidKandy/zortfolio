'use strict';

(function() {
    class MusicDisplay extends HTMLElement {
        connectedCallback() {
            this.style.display = "flex";
            this.style.justifyContent = "center";
            this.style.position = "relative";

            const wrapper = document.createElement("div");
            wrapper.classList.add("wrapper");

            // Background container with blurred image
            const backgroundContainer = document.createElement("div");
            backgroundContainer.classList.add("background-container");
            backgroundContainer.style.backgroundImage = `url("${this.image}")`;

            // Foreground container
            const container = document.createElement("div");
            container.classList.add("container");

            const img = document.createElement("img");
            img.src = this.image;
            img.alt = this.name;

            const titleAndRelease = document.createElement("div");
            titleAndRelease.classList.add("title-and-release");

            const titleLink = document.createElement("a");
            titleLink.href = this.spotify_url;
            titleLink.target = "_blank";
            titleLink.style.textDecoration = "none";

            const title = document.createElement("h3");
            title.textContent = this.name;
            titleLink.appendChild(title);

            const release = document.createElement("h4");
            release.textContent = this.release;

            titleAndRelease.appendChild(titleLink);
            titleAndRelease.appendChild(release);

            container.appendChild(titleAndRelease);
            container.appendChild(img);

            // Add everything inside wrapper
            wrapper.appendChild(backgroundContainer);
            wrapper.appendChild(container);

            const style = document.createElement("style");
            style.textContent = `
                .wrapper {
                    position: relative;
                    width: 100%;
                    max-width: 400px;
                    overflow: hidden;
                    box-shadow: 1px 3px 3px light-dark(rgba(0, 0, 0, 0.4), rgba(200, 200, 200, 0.4));
                    border: 3px double light-dark(var(--light-border), var(--dark-border));
                    transition: all 200ms ease-in, all 400ms ease-out;
                }

                .wrapper:hover {
                    transform: scale(1.005);
                    box-shadow: 2px 4px 2px light-dark(rgba(0, 0, 0, 0.5), rgba(200, 200, 200, 0.5));
                }

                .background-container {
                    position: absolute;
                    top: 0;
                    left: 0;
                    right: 0;
                    bottom: 0;
                    background-size: cover;
                    background-position: center;
                    filter: blur(15px);
                    opacity: 1;
                }

                .container {
                    position: relative;
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    padding: 1rem;
                    text-align: center;
                    z-index: 1;
                    flex-grow: 1;
                    justify-content: space-between;
                }
                
                .container img {
                    max-width: 100%;
                    border-radius: 8px;
                }

                .container a {
                    text-decoration: none;
                    color: #1db954;
                    font-weight: bold;
                }

                .container a:hover {
                    text-decoration: underline;
                }

                .container h3 {
                    display: inline-block;
                    color: var(--secondary-red);
                    text-shadow: 1px 1px 0px var(--offblack);
                }

                .container h3:hover {
                    color: var(--tertiary-blue);
                }

                .container h4 {
                    margin-top: 5px;
                    font-size: 12px;
                    color: var(--offwhite);
                }

                .title-and-release {
                    margin: 1rem 0;
                    background-color: rgba(0, 0, 0, 0.2);
                    padding: 0.5rem;
                    border-radius: 8px;
                }
            `;

            this.attachShadow({ mode: 'open' }).appendChild(style);
            this.shadowRoot.appendChild(wrapper);
        }

        get name() {
            return this.getAttribute("name") || "Unknown";
        }

        get image() {
            return this.getAttribute("image") || "";
        }

        get release() {
            return this.getAttribute("release") || "Unknown Release";
        }

        get spotify_url() {
            return this.getAttribute("spotify_url") || "#";
        }
    }

    customElements.define('music-display', MusicDisplay);
})();
