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
Предварительно поправить файл **/etc/locale.gen** и раскомментировать `en_GB.UTF-8 UTF-8` и другие нужные языки
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
grub-install
grub-mkconfig -o /boot/grub/grub.cfg
```
Для установки из виртуалки, для grub-install нужна опция `--target=x86_64-efi` (если виртуалка грузилась не в UEFI моде). Если установка происходит на флешку, то надо добавить `--removable` чтобы граб не добавлял запись в entry boot в UEFI. Ну и убедиться что EFI раздел монтирован в `/boot/efi` иначе надо указывать явный путь к нему.
Через `efibootmgr` можно явно настроить порядок загрузки в UEFI и даже добавить новые entry boot.

#### Сеть
```
pacman -S networkmanager
systemctl enable NetworkManager
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

Включить сетевой сервис (если до этого не сделал), потом подключиться к сети.
```
systemctl enable --now NetworkManager
nmtui
```

Поставить всё что связано со звуком, затем запустить сервисы.
```
pacman -S pipewire wireplumber
systemctl start --user pipewire
systemctl start --user wireplumber
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

Для Bluetooth:
```
pacman -S bluez
systemctl enable --now bluetooth
```

Для принтера (system-config-printer для GNOME, hplip для HP принтеров):
```
pacman -S cups system-config-printer hplip
systemctl enable --now cups.service
```

Переключение языка на Shift+Alt в GNOME:
```
gsettings set org.gnome.desktop.wm.keybindings switch-input-source "['<Shift>Alt_L']"
```

# Возможные нюансы

#### Проблема с ключами

Нужно просто обновить archlinux-keyring.
```
pacman -S archlinux-keyring
```

#### Пункт из бут меню пропадает ИЛИ grub не находит раздел по uuid

Такое может быть когда по какой-то причине уефи не увидел диск и удалил все невалидные пункты бут меню.

# Шифрование системы

### Форматирование созданных разделов

Создаем и формутируем раздел который шифруем:
```
cryptsetup -v luksFormat /dev/sda3
cryptsetup luksOpen /dev/sda3 root
mkfs.ext4 /dev/mapper/root
```
дальше монтируем эти разделы как и обычно

### Настройка системы на использование шифрования (только тогда когда у нас шифрованный корневой раздел)

Редактируем файл `/etc/mkinitcpio.conf` наша задача добавить в HOOKS:
* `encrypt` после *block* но перед *filesystems*
* `keyboard` перед *autodetect* и перед *encrypt* (но только если устанавливается на внешний диск, потому-что клавиатура запоминается только на том устройстве на котором была установка)

Затем заново генерируем initramfs `mkinitcpio -P`

Редактируем файл `/etc/default/grub` добавляем туда значение для параметра GRUB_CMDLINE_LINUX. В качестве UUID использовать значение шифрованного раздела `/dev/sda3`
```
GRUB_CMDLINE_LINUX="cryptdevice=UUID=00000000-0000-0000-0000-000000000000:root root=/dev/mapper/root"
```
Затем заново генерируем конфиг граба `grub-mkconfig -o /boot/grub/grub.cfg`

# Пример конфигурации для корневой btrfs и шифрованного home

Монтирую нужный ефи раздел.
В корень монтируется бтрфс для снапшотов, логи убираю отдельно чтобы не снапшотить их.
Домашний раздел шифрую и монтирую на этапе загрузки системы. Свап тоже самое но без пароля.

Для информации:
* Ничего не указываю в HOOKS и вообще не трогаю ядро т.к. корневой раздел не зашифрован
* Диски: **nvme0n1** с Linux, **nvme1n1** с Windows
* Юиды: **UUID** юид файловой системы (может не быть, если в разделе нет фс), **PARTUUID** юид гпт раздела (может не быть для виртуальных девайсов)
* В бут меню UEFI используются **PARTUUID** разделов для пути к `*.efi` файлам

```
[karen@arch-pc ~]$ lsblk -o +UUID,PARTUUID
NAME        MAJ:MIN RM   SIZE RO TYPE  MOUNTPOINTS UUID                                 PARTUUID
nvme0n1     259:0    0 476.9G  0 disk                                                   
├─nvme0n1p1 259:1    0   300M  0 part  /efi        594D-1280                            5b0aa7dc-9d35-4643-a1b9-7f50f6061eea
├─nvme0n1p2 259:2    0    12G  0 part                                                   e8930692-64d0-4556-8ab4-8baba583bade
│ └─swap    254:0    0    12G  0 crypt [SWAP]      42f65b50-10b8-4561-be91-1aefc20ee280 
├─nvme0n1p3 259:3    0 284.9G  0 part              f10b25ea-d676-4fd7-8104-838fad16eed9 f3f9c238-4a6c-47a7-b982-052cf757c2be
│ └─home    254:1    0 284.9G  0 crypt /home       0731a994-0138-4f65-8029-858420f691ad 
└─nvme0n1p4 259:4    0 179.7G  0 part  /var/log    182721eb-9ee3-4f4d-9d77-5ed5548eaebc 95b219df-5b6a-47ab-b881-734d49a49a3e
                                       /                                                
```

Домашний раздел монтируется и расшифровывается грабом. А свап каждый раз перетирается рандомными данными при загрузке, и ключ берем просто случайный из рандома.
```
[karen@arch-pc ~]$ cat /etc/crypttab 
home	UUID=f10b25ea-d676-4fd7-8104-838fad16eed9
swap	PARTUUID=e8930692-64d0-4556-8ab4-8baba583bade	/dev/urandom	swap,cipher=aes-xts-plain64,size=256
```

```
[karen@arch-pc ~]$ cat /etc/fstab 

# BTRFS
UUID=182721eb-9ee3-4f4d-9d77-5ed5548eaebc	/         	btrfs     	rw,noatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@	0 0
UUID=182721eb-9ee3-4f4d-9d77-5ed5548eaebc	/var/log  	btrfs     	rw,noatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@var_log	0 0

# Crypto LUKS
/dev/mapper/home	/home     	ext4      	rw,noatime	0 2
/dev/mapper/swap	none      	swap      	defaults  	0 0

# EFI Partition
UUID=594D-1280      	/efi      	vfat      	rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro	0 2
```

Пункты boot menu (все лишнее убрал из вывода):
```
[karen@arch-pc ~]$ efibootmgr 
BootCurrent: 0004
BootOrder: 0004,0003,2002,2001,2003
Boot0004* Arch Linux	HD(1,GPT,5b0aa7dc-9d35-4643-a1b9-7f50f6061eea,0x800,0x96000)/\EFI\arch\grubx64.efi
. . .
```

Пункты меню в конфиге GRUB:
```
menuentry 'Arch Linux' --class arch --class gnu-linux --class gnu --class os $menuentry_id_option 'gnulinux-simple-182721eb-9ee3-4f4d-9d77-5ed5548eaebc' {
	load_video
	set gfxpayload=keep
	insmod gzio
	insmod part_gpt
	insmod btrfs
	search --no-floppy --fs-uuid --set=root 182721eb-9ee3-4f4d-9d77-5ed5548eaebc
	echo	'Loading Linux linux ...'
	linux	/@/boot/vmlinuz-linux root=UUID=182721eb-9ee3-4f4d-9d77-5ed5548eaebc rw rootflags=subvol=@ reboot=efi loglevel=3 quiet
	echo	'Loading initial ramdisk ...'
	initrd	/@/boot/amd-ucode.img /@/boot/initramfs-linux.img
}

### BEGIN /etc/grub.d/30_os-prober ###
menuentry 'Windows Boot Manager (on /dev/nvme0n1p1)' --class windows --class os $menuentry_id_option 'osprober-efi-0669-998A' {
	insmod part_gpt
	insmod fat
	search --no-floppy --fs-uuid --set=root 0669-998A
	chainloader /EFI/Microsoft/Boot/bootmgfw.efi
}
### END /etc/grub.d/30_os-prober ###
```
