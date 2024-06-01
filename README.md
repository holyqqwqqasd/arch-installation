# Установка арча

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

#### Создание сабволумов и монтирование разделов
```
mount /dev/sda3 /mnt
cd /mnt
btrfs subvolume create @
btrfs subvolume create @home
btrfs subvolume create @var_log
cd /
umount /mnt

mount -o noatime,compress=zstd,subvol=@ /dev/sda3 /mnt
mkdir -p /mnt/{home,boot/efi,var/log}
mount -o noatime,compress=zstd,subvol=@home /dev/sda3 /mnt/home
mount -o noatime,compress=zstd,subvol=@var_log /dev/sda3 /mnt/var/log
mount /dev/sda1 /mnt/boot/efi
swapon /dev/sda2
```

#### Установка базы
```
pacstrap -K /mnt base linux linux-firmware
```
Если надо не забыть про `amd-ucode` и или `intel-ucode`

#### Генерация фстаба
```
genfstab -U /mnt >> /mnt/etc/fstab
```
_Из **/etc/fstab** убрать subvolid у монтированных сабволумов_

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
echo 'LANG=en_GB.UTF-8' > /etc/locale.conf
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
Для установки из виртуалки, для grub-install нужна опция `--target=x86_64-efi` (если виртуалка грузилась не в UEFI моде). Если установка происходит не на флешку, то надо убрать `--removable` чтобы граб добавил запись в entry boot в UEFI.

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
# systemctl start --user pipewire-pulse
```

Поставить шрифты
```
pacman -S ttf-ubuntu-font-family noto-fonts noto-fonts-cjk noto-fonts-emoji
```

Для ноутбука поставить оптимизацию расходования заряда батареи:
```
pacman -S tlp
systemctl enable --now tlp
systemctl mask systemd-rfkill.service systemd-rfkill.socket
```

# Возможные нюансы

#### Проблема с ключами

Нужно просто обновить archlinux-keyring.

Еще вариант возможно поможет:
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

#### Пункт из бут меню пропадает

Такое может быть когда либо материнка читает только первый EFI раздел а на другие забивает, либо когда по какой-то причине уефи не увидел диск и удалил все невалидные пункты бут меню.

# Шифрование системы

### Форматирование созданных разделов

Создаем и формутируем раздел который шифруем:
```
cryptsetup -v luksFormat /dev/sda3
cryptsetup luksOpen /dev/sda3 root
mkfs.ext4 /dev/mapper/root
```
дальше монтируем эти разделы как и обычно

### Настройка системы на использование шифрования

Редактируем файл `/etc/mkinitcpio.conf` наша задача добавить в HOOKS:
* `encrypt` после *block* но перед *filesystems*
* `keyboard` перед *autodetect* и перед *encrypt* (но только если устанавливается на внешний диск, потому-что клавиатура запоминается только на том устройстве на котором была установка)

Затем заново генерируем initramfs `mkinitcpio -P`

Редактируем файл `/etc/default/grub` добавляем туда значение для параметра GRUB_CMDLINE_LINUX (или GRUB_CMDLINE_LINUX_DEFAULT). В качестве UUID использовать значение шифрованного раздела `/dev/sda3`
```
GRUB_CMDLINE_LINUX="cryptdevice=UUID=00000000-0000-0000-0000-000000000000:root root=/dev/mapper/root"
```
Затем заново генерируем конфиг граба `grub-mkconfig -o /boot/grub/grub.cfg`
