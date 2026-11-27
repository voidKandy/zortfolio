# Steps taken to setup the VPS

### Security:
Connect SSH: `ssh root@155.138.223.118`
Create deploy user (with password prompted): 
```bash
adduser deploy
usermod -aG sudo deploy
```

**On the macbook:**
```bash
ssh-copy-id deploy@155.138.223.118
ssh -o PasswordAuthentication=no -o PreferredAuthentications=publickey deploy@155.138.223.118
```

Now we harden SSH. We create new config with 00 prefix to make it take priority over all others in case another re-enables passwords: `vi /etc/ssh/sshd_config.d/00-hardening.conf`
Copy/Paste:
```conf
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
AllowUsers deploy
MaxAuthTries 3
```
Then, reset SSH:
```bash
sudo sshd -t && sudo systemctl reload ssh
```
 Ensure it works in a new terminal by signing in as deploy: `ssh deploy@155.138.223.118`
From here on out, this is how you connect. But keep the root access terminal open for the rest of setup.

Now we update the firewall:
```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 80,443/tcp
sudo ufw limit 22/tcp
sudo ufw status verbose
```

Now, we download & install zig:
```bash
wget https://ziglang.org/download/0.17.1/zig-x86_64-linux-0.17.1.tar.xz
sudo mv ~/zig-x86_64-linux-0.17.1 /opt/zig
sudo ln -s /opt/zig/zig /usr/local/bin/zig
rm zig-x86_64-linux-0.17.1.tar.xz
```


Now, switch to a `deploy` terminal to download the website specific stuff.
```bash
git clone https://github.com/voidKandy/zortfolio.git
cd zortfolio
zig build
```



## SSL
I downloaded the ssl package from porkbun.
In order to avoid putting the ssl package on github, I have a local copy on the spacebook and I manually copy/pasted to the VPS. Also, `ssl-bundle` is included in `.gitignore`.
Even though `zyph` has the capability to run https, we are just running it in http. Nginx is handling the certs through https with clients and communicating with the web server through http.


## Nginx Reverse proxy
```bash
sudo apt install nginx
# Create config
sudo vi /etc/nginx/sites-available/zortfolio
```
The config: 
```nginx
server {
    listen 80;
    server_name voidkandy.space www.voidkandy.space;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name voidkandy.space www.voidkandy.space;

    ssl_certificate /home/deploy/zortfolio/ssl-bundle/domain.cert.pem;
    ssl_certificate_key /home/deploy/zortfolio/ssl-bundle/private.key.pem;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Link: `sudo ln -s /etc/nginx/sites-available/zortfolio /etc/nginx/sites-enabled/`

Then enable the proxy:
```bash
sudo nginx -t
sudo systemctl reload nginx
```


## Setting up systemctl
`sudo vi /etc/systemd/system/zortfolio.service`


```ini
[Unit]
Description=Zortfolio
After=network.target

[Service]
Type=simple
User=deploy
WorkingDirectory=/home/deploy/zortfolio
EnvironmentFile=/home/deploy/zortfolio/.env
ExecStart=/home/deploy/zortfolio/zig-out/bin/zortfolio
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```


```bash
sudo systemctl daemon-reload
sudo systemctl enable zortfolio
sudo systemctl start zortfolio
```

If you ever need to see live logs: `sudo journalctl -u zortfolio -f`


## Automated deployments
I've createdm `deploy.sh` in the root of the repo. It is only meant to be called by the vps itself and has no real use for the dev environment. All it does is sync with `dev` branch and then restart the zortfolio service.

In order to make sure a password isn't prompted, we need to add the zortfolio binary to `sudoers`: `sudo visudo -f /etc/sudoers.d/zortfolio`
and paste: `deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart zortfolio`


**create a dedicated ssh key on the spacebook:** `ssh-keygen -t ed25519 -f ~/.ssh/zortfolio_deploy -C "github-actions-zortfolio"`
Then, add that key to the vps:
```bash
cat ~/.ssh/zortfolio_deploy.pub | ssh deploy@155.138.223.118 \
'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
```
Double check that they key worked, the following command should connect you: `ssh -i ~/.ssh/zortfolio_deploy deploy@155.138.223.118`


### Set up gitlab side
`VPS_KNOWN_HOSTS` and `VPS_SSH_KEY` need to be added to the ci variables from within the browser.
`VPS_SSH_KEY` is the output of: `cat ~/.ssh/zortfolio_deploy`
`VPS_KNOWN_HOSTS` is the output of: `ssh-keyscan -H 155.138.223.118`
(both orun on spacebook)

Create `.gitlab-ci.yml`
```yml
variables:
    VPS_HOST:	155.138.223.118
    VPS_USER:	deploy

stages:
  - deploy

deploy:
  stage: deploy
  image: alpine:latest

  before_script:
    - apk add --no-cache openssh-client
    - mkdir -p ~/.ssh
    - chmod 700 ~/.ssh
    - cp "$VPS_SSH_KEY" ~/.ssh/id_ed25519
    - chmod 600 ~/.ssh/id_ed25519
    - cp "$VPS_KNOWN_HOSTS" ~/.ssh/known_hosts
    - chmod 600 ~/.ssh/known_hosts

  script:
    - ssh "$VPS_USER@$VPS_HOST" "/home/deploy/zortfolio/deploy.sh"

  rules:
    - if: '$CI_COMMIT_BRANCH == "dev"'

```


