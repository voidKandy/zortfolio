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
A new .env variable called `ENVIRONMENT` was added, it must be either 0 or 1. 0 is dev, 1 is prod. This is used to select the correct certificates. Don't forget, when using dev, make sure that you add the `local_ssl/localCA.crt` to your trusted in your browser.

Before getting nginx setup, you can sanity test the server serves up correctly by running the server and going to https://www.voidkandy.space:3000


## Todo list
[x] - ssl certs
[ ] - nginx
[ ] - remove Dockerfile

