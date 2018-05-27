# NimForum setup

This document describes the steps needed to setup a working NimForum instance.

## Requirements

* Ubuntu 16.04+
* Some Linux knowledge

## Installation

Begin by downloading the latest NimForum release from
[here](https://github.com/nim-lang/nimforum/releases). The macOS releases are
mainly provided for testing.

Extract the downloaded tarball on your server. These steps can be done using
the following commands:

```
wget TODO
tar -xf TODO
```

Then ``cd`` into the forum's directory:

```
cd TODO
```

### Dependencies

The following may need to be installed on your server:

```
sudo apt install libsass-dev sqlite3
```

## Configuration and DB creation

The NimForum release comes with a handy ``setup_nimforum`` program. Run
it to begin the setup process:

```
./setup_nimforum --setup
```

The program will ask you multiple questions which will require some
additional setup, including mail server info and recaptcha keys. You can
just specify dummy values if you want to play around with the forum as
quickly as possible and set these up later.

This program will create a ``nimforum.db`` file, this contains your forum's
database. It will also create a ``forum.json`` file, you can modify this
file after running the ``setup_nimforum`` script if you've made any mistakes
or just want to change things.

## Running the forum

Executing the forum is simple, just run the ``forum`` binary:

```
./forum
```

The forum will start listening to HTTP requests on port 5000 (by default, this
can be changed in ``forum.json``).

On your server you should set up a separate HTTP server. The recommended choice
is nginx. You can then use it as a reverse proxy for NimForum.

### HTTP server

#### nginx

Once you have nginx installed on your server, you will need to configure it.
Create a ``forum.hostname.com`` file (replace the hostname with your forum's
hostname) inside ``/etc/nginx/sites-available/``.

Place the following inside it:

```
server {
        server_name forum.hostname.com;
        autoindex off;

        location / {
                proxy_pass http://localhost:5000;
                proxy_set_header Host $host;
                proxy_set_header X-Real_IP $remote_addr;
        }
}
```

Again, be sure to replace ``forum.hostname.com`` with your forum's
hostname.

You should then create a symlink to this file inside ``/etc/nginx/sites-enabled/``:

```
ln -s /etc/nginx/sites-available/<forum.hostname.com> /etc/nginx/sites-enabled/<forum.hostname.com>
```

Then restart nginx by running ``sudo systemctl restart nginx``.

### Supervisor

#### systemd

In order to ensure the forum is always running, even after a crash or a server
reboot, you should create a systemd service file.

Create a new file called ``nimforum.service`` inside ``/lib/systemd/system/nimforum.service``.

Place the following inside it:

```
[Unit]
Description=nimforum
After=network.target httpd.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/home/<user>/nimforum-2.0.0/ # MODIFY THIS
ExecStart=/usr/bin/stdbuf -oL /home/<user>/nimforum-2.0.0/forum # MODIFY THIS
# Restart when crashes.
Restart=always
RestartSec=1

User=dom

StandardOutput=syslog+console
StandardError=syslog+console

[Install]
WantedBy=multi-user.target
```

**Be sure to specify the correct ``WorkingDirectory`` and ``ExecStart``!**

You can then enable and start the service by running the following:

```
sudo systemctl enable nimforum
sudo systemctl start nimforum
```

To check that everything is in order, run this:

```
systemctl status nimforum
```

You should see something like this:

```
● nimforum.service - nimforum
   Loaded: loaded (/lib/systemd/system/nimforum.service; enabled; vendor preset: enabled)
   Active: active (running) since Fri 2018-05-25 22:09:59 UTC; 1 day 22h ago
 Main PID: 21474 (forum)
    Tasks: 1
   Memory: 55.2M
      CPU: 1h 15min 31.905s
   CGroup: /system.slice/nimforum.service
           └─21474 /home/dom/nimforum/src/forum
```

## Conclusion

That should be all you need to get started. Your forum should now be accessible
via your hostname, assuming that it points to your VPS' IP address.