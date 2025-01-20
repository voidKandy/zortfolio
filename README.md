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
