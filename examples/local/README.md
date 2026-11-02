# Local example

Applies circuit-nginx to a throwaway Rocky Linux 10 container with systemd. You need Conn3x and Podman.

```sh
./up.sh
conn3x init
conn3x apply
conn3x plan
```

The second plan says `No changes.` To look at the result:

```sh
curl http://127.0.0.1:8080/
```

`up.sh` listens on `127.0.0.1:2222`, and forwards `127.0.0.1:8080` to nginx. Set `PORT` to use another SSH port, and pass the same port to Conn3x with `-var port=PORT`. Set `WEB_PORT` to move the other. Set `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses.

`./down.sh` removes the container, the key and the state.
