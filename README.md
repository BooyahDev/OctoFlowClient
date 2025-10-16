# Loopback IP Configuration Script

このスクリプトは、Linuxシステムでloopbackインターフェースに仮想IP（VIP）を設定し、必要なシステム設定を自動で構成するためのツールです。主にKeepalivedやHAProxyなどの高可用性構成で使用されます。

## 機能

1. **Loopback IP設定**: 指定されたIPアドレスをloopbackインターフェース（lo）に追加
2. **sysctl設定**: ARP応答制御とrp_filter設定の自動構成
3. **systemdサービス作成**: システム再起動後も設定を維持するためのサービス作成
4. **重複チェック**: 既に設定済みのIPアドレスに対する適切な処理

## 設定される項目

### sysctl設定
- `net.ipv4.conf.all.arp_ignore = 1`
- `net.ipv4.conf.all.arp_announce = 2`
- `net.ipv4.conf.default.arp_ignore = 1`
- `net.ipv4.conf.default.arp_announce = 2`
- `net.ipv4.conf.all.rp_filter = 0`
- `net.ipv4.conf.default.rp_filter = 0`
- `net.ipv4.ip_forward = 0`

### systemdサービス
- サービス名: `add-vip.service`
- 自動起動設定
- 既存IP確認機能付き
- **自動削除機能**: サービス停止時にIPアドレスを自動削除

## 使用方法

### 1. ワンライナー実行（推奨）

```bash
sudo /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/BooyahDev/OctoFlowClient/refs/heads/master/setup.sh)" -- 10.0.200.102
```

### 2. 対話式実行

```bash
sudo ./setup.sh
```

実行後、IPアドレスの入力を求められます：
```
Enter the loopback IP to configure (e.g., 192.168.1.100 or 192.168.1.100/32): 10.0.200.102
```

### 3. 引数指定実行

```bash
sudo ./setup.sh 10.0.200.102
```

または、CIDR記法も対応：
```bash
sudo ./setup.sh 10.0.200.102/32
```

## 実行例

### 正常な実行例
```bash
$ sudo ./setup.sh 10.0.200.102
Using loopback IP from argument: 10.0.200.102
Configuring loopback IP: 10.0.200.102
Successfully added 10.0.200.102 to the loopback interface.
Configuring sysctl settings for ARP and rp_filter...
net.ipv4.conf.all.arp_ignore = 1
net.ipv4.conf.all.arp_announce = 2
net.ipv4.conf.default.arp_ignore = 1
net.ipv4.conf.default.arp_announce = 2
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
Persisting sysctl settings to /etc/sysctl.d/99-keepalived.conf...
Creating systemd service to manage VIP 10.0.200.102...
Successfully created and started add-vip.service.
Successfully configured loopback IP 10.0.200.102 with all settings.
```

### 既に設定済みの場合
```bash
$ sudo ./setup.sh 10.0.200.102
Using loopback IP from argument: 10.0.200.102
Configuring loopback IP: 10.0.200.102
The IP 10.0.200.102 is already configured on the loopback interface.
Configuring sysctl settings for ARP and rp_filter...
...
Warning: Failed to start add-vip.service, but the IP may already be configured.
IP 10.0.200.102 is already configured on the loopback interface. Service creation completed.
Successfully configured loopback IP 10.0.200.102 with all settings.
```

## 設定確認

### IPアドレス確認
```bash
ip addr show lo
```

### systemdサービス確認
```bash
systemctl status add-vip.service
```

### sysctl設定確認
```bash
sysctl net.ipv4.conf.all.arp_ignore
sysctl net.ipv4.conf.all.arp_announce
sysctl net.ipv4.conf.all.rp_filter
```

## トラブルシューティング

### よくある問題

1. **権限エラー**
   ```
   Failed to add IP to the loopback interface. Please check your permissions.
   ```
   → `sudo`で実行してください

2. **無効なIPアドレス**
   ```
   Invalid IP format. Please enter a valid IPv4 address (with optional /32 CIDR notation).
   ```
   → 正しいIPv4形式で入力してください（例：192.168.1.100）

3. **systemdサービス起動失敗**
   ```
   Warning: Failed to start add-vip.service, but the IP may already be configured.
   ```
   → 通常は問題ありません。IPアドレスが既に設定されている場合の正常な動作です

### ログ確認
```bash
journalctl -xeu add-vip.service
```

## 設定削除

### 簡単な削除方法（推奨）

systemdサービスを停止するだけで、loopbackインターフェースからIPアドレスが自動的に削除されます：

```bash
# VIPアドレスを削除（サービス停止で自動実行）
sudo systemctl stop add-vip.service

# サービスの自動起動を無効化
sudo systemctl disable add-vip.service
```

### 完全削除

systemdサービスファイルも完全に削除する場合：

```bash
# サービス停止・無効化・削除
sudo systemctl stop add-vip.service
sudo systemctl disable add-vip.service
sudo rm /etc/systemd/system/add-vip.service
sudo systemctl daemon-reload
```

### 手動でのIP削除

必要に応じて手動でIPアドレスを削除：
```bash
sudo ip addr del 10.0.200.102/32 dev lo
```

## 対応OS

- Ubuntu 18.04以降
- CentOS 7以降
- RHEL 7以降
- その他systemdを使用するLinuxディストリビューション

## 注意事項

- 必ず`sudo`権限で実行してください
- 既存のネットワーク設定に影響を与える可能性があります
- 本番環境での実行前にテスト環境での動作確認を推奨します
- sysctl設定は`/etc/sysctl.d/99-keepalived.conf`に永続化されます

## ライセンス

MIT License

## 貢献

プルリクエストやイシューの報告は歓迎します。

## 関連ドキュメント

- [Keepalived Documentation](https://keepalived.readthedocs.io/)
- [Linux Advanced Routing & Traffic Control](https://lartc.org/)
- [systemd.service Manual](https://www.freedesktop.org/software/systemd/man/systemd.service.html)