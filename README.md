# Установка арча

### База

Настройка времени и разметка диска
```
timedatectl set-ntp true
cfdisk --zero /dev/sda
```

Разметить в GPT диск следующим образом:
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
