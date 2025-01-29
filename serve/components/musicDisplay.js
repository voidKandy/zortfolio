'use strict';

(function() {
    class MusicDisplay extends HTMLElement {
        connectedCallback() {
            this.style.display="flex";
            this.style.justifyContent="center";

            const container = document.createElement("div");
            container.classList.add('container');

            this.loadAndBlurImage(this.image, 20).then((blurredUrl) => {
                container.style.backgroundImage = `url("${blurredUrl}")`;
            });

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
            
 
            const style = document.createElement("style");
            style.textContent = `
                .container {
                    flex-grow: 1;
                    display: flex;
                    flex-direction: column;
                    justify-content: space-between;
                    box-shadow: 1px 3px 3px light-dark(rgba(0, 0, 0, 0.4), rgba(200, 200, 200, 0.4));
                    border: 3px double light-dark(var(--light-border), var(--dark-border));
                    padding: 1rem;
                    margin: 1rem;
                    text-align: center;
                    transition: all 200ms ease-in, all 400ms ease-out;
                }

                .container:hover {
                    transform: scale(1.005);
                    box-shadow: 2px 4px 2px light-dark(rgba(0, 0, 0, 0.5), rgba(200, 200, 200, 0.5));
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
                    margin: 1rem 0rem;
                    background-color: rgba(0,0,0,0.2);
                    padding: 0.5rem;
                    border-radius: 8px;
                }
            `;
            this.attachShadow({ mode: 'open' }).appendChild(style);
            this.shadowRoot.appendChild(container);

        }


        async loadAndBlurImage(imageUrl, blurAmount) {
            try {
                const response = await fetch(imageUrl);
                const blob = await response.blob();
                return await this.blurImage(blob, blurAmount);
            } catch (error) {
                console.error("Failed to load or blur image:", error);
                return imageUrl; // Fallback to original image if blurring fails
            }
        }

        blurImage(blob, blurAmount = 10) {
            return new Promise((resolve) => {
                const img = new Image();
                img.src = URL.createObjectURL(blob);
                img.onload = () => {
                    const canvas = document.createElement("canvas");
                    const ctx = canvas.getContext("2d");

                    // Set canvas size
                    canvas.width = img.width;
                    canvas.height = img.height;

                    // Apply blur using CSS filter before drawing
                    ctx.filter = `blur(${blurAmount}px)`;
                    ctx.drawImage(img, 0, 0, img.width, img.height);

                    // Convert canvas to a new BLOB and resolve
                    canvas.toBlob((blurredBlob) => {
                        resolve(URL.createObjectURL(blurredBlob));
                    }, "image/png");
                };
            });
        }

        get name() {
            let val = this.getAttribute("name");
            if (val == null) {
                console.log("name attribute was not passed");
            }
            return val;
        }

        get image() {
            let val = this.getAttribute("image");
            if (val == null) {
                console.log("image attribute was not passed");
            }
            return val;
        }

        get release() {
            let val = this.getAttribute("release");
            if (val == null) {
                console.log("release attribute was not passed");
            }
            return val;
        }

        get spotify_url() {
            let val = this.getAttribute("spotify_url");
            if (val == null) {
                console.log("spotify_url attribute was not passed");
            }
            return val;
        }

    }

    customElements.define('music-display', MusicDisplay);
})();
