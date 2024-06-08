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

Включить сетевой сервис, потом подключиться к сети.
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

#### Пункт из бут меню пропадает ИЛИ grub не находит раздел по uuid

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

Редактируем файл `/etc/default/grub` добавляем туда значение для параметра GRUB_CMDLINE_LINUX. В качестве UUID использовать значение шифрованного раздела `/dev/sda3`
```
GRUB_CMDLINE_LINUX="cryptdevice=UUID=00000000-0000-0000-0000-000000000000:root root=/dev/mapper/root"
```
Затем заново генерируем конфиг граба `grub-mkconfig -o /boot/grub/grub.cfg`

# Пример конфигурации для корневой btrfs и шифрованного home

Монтирую ефи раздел с первого диска с виндой (дуалбут).
В корень монтируется бтрфс для снапшотов, логи убираю отдельно чтобы не снепшотить их.
Домашний раздел шифрую и монтирую на этапе загрузки системы. Свап тоже самое но без пароля.
```
[karen@arch-pc ~]$ lsblk -f
NAME        FSTYPE      FSVER LABEL UUID                                 FSAVAIL FSUSE% MOUNTPOINTS
nvme1n1                                                                                 
├─nvme1n1p1 vfat        FAT32       594D-1280                                           
├─nvme1n1p2                                                                             
│ └─swap    swap        1     swap  69c0c0e6-e373-4924-9e95-97309356c0e4                [SWAP]
├─nvme1n1p3 crypto_LUKS 2           f10b25ea-d676-4fd7-8104-838fad16eed9                
│ └─home    ext4        1.0         0731a994-0138-4f65-8029-858420f691ad    263G     1% /home
└─nvme1n1p4 btrfs                   182721eb-9ee3-4f4d-9d77-5ed5548eaebc  173.5G     3% /var/log
                                                                                        /
nvme0n1                                                                                 
├─nvme0n1p1 vfat        FAT32       0669-998A                              35.4M    63% /efi
├─nvme0n1p2                                                                             
├─nvme0n1p3 ntfs                    16606AD9606ABF5D                                    
└─nvme0n1p4 ntfs                    460CF1330CF11E9D                                    
```

Домашний раздел монтируется и расшифровывается грабом. А свап каждый раз перетирается рандомными данными при загрузке, и ключ берем просто случайный из рандома.
```
[karen@arch-pc ~]$ sudo cat /etc/crypttab 
[sudo] password for karen: 

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

# /dev/nvme0n1p1
UUID=0669-998A      	/efi      	vfat      	rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro	0 2
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
	linux	/@/boot/vmlinuz-linux root=UUID=182721eb-9ee3-4f4d-9d77-5ed5548eaebc rw rootflags=subvol=@  loglevel=3 quiet
	echo	'Loading initial ramdisk ...'
	initrd	/@/boot/amd-ucode.img /@/boot/initramfs-linux.img
}

menuentry 'Windows Boot Manager (on /dev/nvme0n1p1)' --class windows --class os $menuentry_id_option 'osprober-efi-0669-998A' {
	insmod part_gpt
	insmod fat
	search --no-floppy --fs-uuid --set=root 0669-998A
	chainloader /EFI/Microsoft/Boot/bootmgfw.efi
}
```
