[Index](../mimis/index.html) [`Org`](../mimis/index.org)

Backup your existing nvim config.

``` bash
mv ~/.config/nvim{,.bak}
```

Backup existing nvim state.

``` bash
mv ~/.local/share/nvim{,.bak}
mv ~/.local/state/nvim{,.bak}
mv ~/.cache/nvim{,.bak}
```

Clone this repo.

``` bash
git clone git@github.com:markwoodhall/mimis.git ~/.config/nvim
```

Run the install script.

``` bash
cd ~/.config/nvim
./bin/mimis install
```

Run nvim.

``` bash
nvim
```

Check out mimis help.

``` bash
:help mimis
```
