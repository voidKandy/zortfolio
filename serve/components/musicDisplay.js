'use strict';

(function() {
    class MusicDisplay extends HTMLElement {
        constructor() {
            super();
            this.attachShadow({ mode: 'open' });
        }

        connectedCallback() {
            this.render();
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

        render() {
            this.shadowRoot.innerHTML = `
                <style>
                    .music-tile {
                        display: flex;
                        flex-direction: column;
                        align-items: center;
                        width: 150px;
                        border: 1px solid #ddd;
                        border-radius: 8px;
                        padding: 10px;
                        text-align: center;
                    }

                    .music-tile img {
                        max-width: 100%;
                        border-radius: 8px;
                    }

                    .music-tile a {
                        text-decoration: none;
                        color: #1db954;
                        font-weight: bold;
                    }

                    .music-tile a:hover {
                        text-decoration: underline;
                    }

                    .music-tile .name {
                        margin-top: 10px;
                        font-size: 14px;
                        font-weight: bold;
                    }

                    .music-tile .release {
                        margin-top: 5px;
                        font-size: 12px;
                        color: #666;
                    }
                </style>
                <div class="music-tile">
                    <img src="${this.image}" alt="${this.name}">
                    <a href="${this.spotify_url}" target="_blank">
                        <div class="name">${this.name}</div>
                    </a>
                    <div class="release">${this.release}</div>
                </div>
            `;
        }
    }

    customElements.define('music-display', MusicDisplay);
})();
