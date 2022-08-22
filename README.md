# Установка арча

#### Настройка времени
```
timedatectl set-ntp true
```

#### Разметить в GPT диск следующим образом:
```
cfdisk --zero /dev/sda
```
  Partition | Type | Size | Mount
  --- | --- | --- | ---
  /dev/sda1 | EFI System | At least 300 MiB | /boot/efi
  /dev/sda2 | Linux swap | More than 512 MiB | [SWAP]
  /dev/sda3 | Linux filesystem | Remainder of the device | /

Форматирование созданных разделов
```
mkfs.fat -F 32 /dev/sda1
mkswap /dev/sda2
mkfs.btrfs -f /dev/sda3
```

#### Создание сабволумов в бтрфс и их монтирование
```
mount /dev/sda3 /mnt
cd /mnt
btrfs subvolume create @
btrfs subvolume create @home
cd /
umount /mnt
mount -o noatime,compress=zstd,subvol=@ /dev/sda3 /mnt
mkdir -p /mnt/{home,boot/efi}
mount -o noatime,compress=zstd,subvol=@home /dev/sda3 /mnt/home
```

Монтируем остальные разделы
```
mount /dev/sda1 /mnt/boot/efi
swapon /dev/sda2
```

#### Установка базы
```
pacstrap /mnt base linux linux-firmware amd-ucode intel-ucode
```
_**!!! для бтрфс !!!** Не забыть убрать fsck из HOOKS в **/etc/mkinitcpio.conf** и выполнить команду `mkinitcpio -P` когда арчрутнемся в систему_

#### Генерация фстаба
```
genfstab -U /mnt >> /mnt/etc/fstab
```
_**!!! для бтрфс !!!** Из **/etc/fstab** убрать subvolid у монтированных сабволумов_

#### chroot
```
arch-chroot /mnt
```

#### Таймзона
```
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
```

#### Установить хардварные часы в UTC
```
hwclock --systohc
```

#### Локализация
Предварительно поправить файл **/etc/locale.gen** и раскомментировать `en_US.UTF-8 UTF-8` и другие нужные языки
```
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo -e 'KEYMAP=ru\nFONT=cyr-sun16' > /etc/vconsole.conf
```

#### Хостнейм
```
echo 'arch-pc' > /etc/hostname
```

#### Загрузчик
```
pacman -S grub efibootmgr
grub-install --removable
grub-mkconfig -o /boot/grub/grub.cfg
```
Для установки из виртуалки, для grub-install нужна опция `--target=x86_64-efi`. Если установка происходит не на флешку, то надо убрать `--removable`

#### Сеть
```
pacman -S networkmanager
```

#### Не забыть установить руту пароль
```
passwd
```

#### Выходим и ребутаемся
```
exit
umount -R /mnt
reboot
```

# Настройка рабочей системы

Включить сетевой сервис, потом подключиться к сети. Если нужен отдельный апплет, то установить **network-manager-applet**
```
systemctl enable --now NetworkManager
nmtui
```

Поставить всё что связано со звуком, затем запустить сервисы. Если нужен отдельная утилита для настройки аудио, то установить **pavucontrol** (ему нужен pipewire-pulse)
```
pacman -S pipewire pipewire-pulse wireplumber
systemctl start --user pipewire
systemctl start --user wireplumber
systemctl start --user pipewire-pulse
```

Поставить шрифты
```
pacman -S ttf-ubuntu-font-family noto-fonts noto-fonts-cjk noto-fonts-emoji
```

# Конфиги

```
ln -s $PWD/config/i3/config ~/.config/i3/config
ln -s $PWD/config/picom/picom.conf ~/.config/picom/picom.conf
ln -s $PWD/config/alacritty/alacritty.yml ~/.config/alacritty/alacritty.yml
ln -s $PWD/config/.zshrc ~/.zshrc
ln -s $PWD/config/polybar/launch.sh ~/.config/polybar/launch.sh
ln -s $PWD/config/polybar/config.ini ~/.config/polybar/config.ini
```

# Возможные нюансы

* Если долго не обновлять систему, возможно все ключи протухнут. Тогда как вариант может помочь полное обновление ключей:
```
rm -rf /etc/pacman.d/gnupg/*
sudo pacman -Scc
sudo pacman-key --init
sudo pacman-key --populate archlinux
для проверки потом sudo pacman -Sy archlinux-keyring
sudo pacman -Syu
```
либо можно попробовать так:
```
sudo pacman -Sy gnupg archlinux-keyring
sudo pacman -Syu
pacman-key –refresh-keys
```
