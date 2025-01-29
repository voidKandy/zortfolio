# Zortfolio
Welcome to the repo for my [portfolio website](www.voidkandy.space)

I built this project as a way to learn the Zig programming language, and I had a lot of fun writing it. I tried to take a 'vanilla first' approach to all of the frontend, this entails:
+ Vanilla CSS
+ Vanilla JS Web Compponents
+ HTMX for routing

## zig + htmx + web-components
An incredible combination.
We don't even have to use html templates

## Web components
zig templates for js web components, but not for html


### routesNav
#### Required Attributes
* routes - comma separated list of routes to add
* target - the elemement that routes will insert partials. must be an ID ex/ '#route-content'
#### Optional Attributes
* defaultRoute - the route to default to, must be a route present in 'routes'. If one is not present, defaults to the 0th route passed in routes
* swap - `hx-swap` strategy, defaults to `innerHTML`
* currentRoute - the route that should currently be rendered. If not included *OR* an empty string, will fallback to defaultRoute.
