'use strict';

(function() {
    class RoutesNav extends HTMLElement {
        connectedCallback() {
            this.routesContainer = document.createElement('div');
            this.routesContainer.id = "routes-container"

            const routes = this.routes;
            const target = this.target;
            const swap = this.swap;
            const defaultRoute = this.defaultRoute;

            this.prevRoute = null;

            if (routes.length == 0) {
                console.log("did not pass any routes")
                return;
            }


            this.routeButtonMap = new Map();
            routes.forEach(route => {
                const button = document.createElement("button");
                button.textContent = route;
                button.classList.add("route-button");
                button.id = `${route}_route`;
                button.setAttribute("hx-get", `/${route}`);
                button.setAttribute("hx-target", target);
                button.setAttribute("hx-swap", swap);

                button.addEventListener("htmx:xhr:loadend", () => {
                    console.log(`${route} loadend`);
                    this.prevRoute = this.updateCurrentRoute(route);
                    this.updateButtonStyles(route);
                });

                this.routeButtonMap.set(route, button);
                this.routesContainer.appendChild(button);

            })



            this.appendChild(this.routesContainer);

            document.addEventListener('DOMContentLoaded', () => {
                if (this.currentRoute == null) {
                    console.log("setting route to default")
                    this.updateCurrentRoute(defaultRoute);
                }

                if (this.prevRoute != this.currentRoute) {
                    this.sendClickToButton(this.currentRoute);
                }

            })

        }

        /**
         * updates current route, returning previous
         * @param {string} route - the route to set as current
         * @returns {string | null}
         * */
        updateCurrentRoute(route) {
            const prev = localStorage.getItem('route');
            localStorage.setItem('route', route);
            return prev;
        }

        /**
         * This triggers after htmx:xhr:loadend, which means it triggers right after any of the route buttons are 
         * clicked 
         * @param {string} activeRoute - which button will be updated
         * */
        updateButtonStyles(activeRoute) {
            const buttons = this.routeButtonMap.values();
            console.log("updating styles");
            buttons.forEach(button => {
                console.log(button);
                if (button.textContent === activeRoute) {
                    console.log("setting");
                    button.textContent = `* ${activeRoute}`;  // Prepend a '*' to active route
                } else {
                    console.log("removing");
                    button.textContent = button.textContent.replace("* ", "");  // Remove '*' from inactive routes
                }
            });
        }

        sendClickToButton(route) {
            const b = this.routeButtonMap.get(route);

            if (!b) {
                console.log("could not get button from route: ", route);
                return;
            }

            console.log("clicking ", route);
            b.click();


        }

        get currentRoute() {
            return localStorage.getItem('route');
        }

        get routes() {
            const routesStr = this.getAttribute('routes') || "";
            const routes = routesStr.split(',').map(route => route.trim());
            return routes;
        }

        get defaultRoute() {
            return this.getAttribute('defaultRoute') || this.routes[0];
        }

        get target() {
            const target = this.getAttribute('target');
            if (target == null) {
                console.log("you should pass a target with a routes-nav component target")
            }
            return target || "";
        }

        get swap() {
            return this.getAttribute('swap') || "innerHTML";
        }

    }

    // let the browser know about the custom element
    customElements.define('routes-nav', RoutesNav);
})();
