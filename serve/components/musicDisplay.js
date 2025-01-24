'use strict';

(function() {
    class MusicDisplay extends HTMLElement {
        constructor() {
            super();
            this.attachShadow({ mode: 'open' });
        }


        async connectedCallback() {
          const client_id = '';
          const client_secret = '';

          // Use btoa() instead of Buffer for Base64 encoding in the browser
          const credentials = btoa(client_id + ':' + client_secret);

          const authOptions = {
            method: 'POST',
            headers: {
              'Authorization': 'Basic ' + credentials,
              'Content-Type': 'application/x-www-form-urlencoded'
            },
            body: new URLSearchParams({
              grant_type: 'client_credentials'
            }).toString()
          };

          try {
            const response = await fetch('https://accounts.spotify.com/api/token', authOptions);
            if (response.ok) {
              const data = await response.json();
              const token = data.access_token;
              console.log('Token:', token);
              // You can now use the token to make further Spotify API requests
            } else {
              console.error('Failed to fetch token:', response.status, response.statusText);
            }
          } catch (error) {
            console.error('Error fetching token:', error);
          }
        }
    }

    customElements.define('music-display', MusicDisplay);
})();
