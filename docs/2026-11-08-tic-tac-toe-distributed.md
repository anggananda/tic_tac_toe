# Rencana Pembuatan Tic-Tac-Toe Terdistribusi (Elixir + Phoenix)

## Tujuan
Demo konsep distributed programming: dua host berbeda terhubung melalui jaringan, permainan tic-tac-toe berjalan real-time antar pemain di host yang berbeda, komunikasi lintas node menggunakan Erlang/Elixir distribution.

## Dasar yang Sudah Ada
Project `tic_tac_toe` saat ini adalah Phoenix web app single-node (satu host). Ada board, controller, view, dan basic Phoenix setup. Belum ada game state terdistribusi dan belum ada koneksi antar node.

## Fase 1: Game Logic di Satu Node (GenServer)
- Buat `TicTacToe.Game` GenServer yang menyimpan state papan (3x3), giliran pemain, dan pemenang.
- Fungsi: `start_link/0`, `join/2`, `make_move/3`, `reset/1`.
- Papan state disimpan di dalam GenServer, satu GenServer = satu pertandingan.
- Tes secara lokal di satu node dulu.

## Fase 2: Real-Time di Satu Node (Phoenix Channels)
- Buat `TicTacToeWeb.GameChannel`.
- Event: `join` (gabung ke room game), `make_move` (pemain klik kotak), broadcast state papan ke lawan secara real-time.
- Satu channel topic per game ID.
- Pemain A dan B connect via WebSocket ke Phoenix server yang sama.

## Fase 3: Distribusi Antar Dua Host (Erlang Node Distribution)
- Setiap host diinisialisasi sebagai node Erlang dengan nama unik: `tic@host-a` dan `tic@host-b`.
- Atur `.erlang.cookie` yang sama di kedua host agar node boleh saling terhubung.
- Gunakan `Node.connect/1` (atau otomatis lewat `--connect-all` di release config) untuk menyambungkan host A dan host B.
- Proses GenServer game bisa dijalankan di node mana pun; pesan lintas node dikirim lewat Erlang distribution (TCP).
- Uji: `Node.spawn_link/2` atau `GenServer.call` lintas node dari host A ke host B.

## Fase 4: Phoenix Channels Multi-Host (PubSub Terdistribusi)
- Setiap host menjalankan Phoenix endpoint sendiri dengan WebSocket.
- Konfigurasikan `Phoenix.PubSub` agar pesan channel melintasi node (misalnya `Phoenix.PubSub.PG2` atau `libcluster`).
- `Phoenix.Presence` melacak pemain online di seluruh klaster (siapa di host A, siapa di host B).
- Alur: Pemain di Host A klik kotak → WebSocket ke host A → pubsub distribusi → host B → WebSocket ke lawan di Host B. Real-time.

## Fase 5: Build & Deploy ke Dua Host (mix release)
- Di satu mesin build: `mix release` (dengan ERTS included, default).
- Hasil: folder `_build/prod/rel/tic_tac_toe/` yang self-contained (tidak perlu install Elixir/Erlang di target).
- Salin folder release ke Host A dan Host B.
- Jalankan di masing-masing host sebagai node terpisah:
  - Host A: `bin/tic_tac_toe start --name tic@host-a --cookie <cookie>`
  - Host B: `bin/tic_tac_toe start --name tic@host-b --cookie <cookie>`
- Buka firewall: port EPMD (4369) dan port range distribusi Erlang agar kedua host saling dijangkau.

## Fase 6: Uji Coba & Edge Case Distributed
- Dua pemain di host berbeda main secara bersamaan, gerakan muncul real-time di lawan.
- Satu host terputus dari jaringan (partisi): apa yang terjadi pada game berjalan?
- Satu node mati selama permainan: apakah state hilang atau bisa dialihkan (failover)?
- Duasi klik hampir bersamaan dari dua host: manajemen giliran (turn locking).
- Latensi jaringan antar host terlihat dalam respons gerakan.

## Checklist Implementasi
- [x] `TicTacToe.Game` GenServer (board, turn, winner, validasi gerakan)
- [x] `TicTacToeWeb.GameChannel` (join, make_move, broadcast via PubSub)
- [x] Konfigurasi node name dan cookie untuk host A + host B (config.exs, runtime.exs)
- [x] `TicTacToe.Cluster` untuk koneksi antar node (`Node.connect/1`)
- [x] `TicTacToe.PubSub` terdistribusi (sudah ada, siap untuk node terhubung)
- [x] `mix release` dengan ERTS (berhasil di-build)
- [ ] Jalankan release di 2 host, uji permainan real-time
- [ ] Uji edge case: putus jaringan, node mati, duasi klik

## File yang Dibuat/Diubah

### Baru
- `lib/tic_tac_toe/game.ex` — GenServer untuk state permainan (board, turn, winner)
- `lib/tic_tac_toe/cluster.ex` — Koneksi Erlang node distribution
- `lib/tic_tac_toe_web/channels/game_channel.ex` — Phoenix Channel untuk real-time
- `lib/tic_tac_toe_web/user_socket.ex` — UserSocket untuk channel
- `lib/tic_tac_toe_web/controllers/game_controller.ex` — Controller halaman game
- `lib/tic_tac_toe_web/controllers/game_html.ex` — View HTML untuk game
- `lib/tic_tac_toe_web/controllers/game_html/index.html.heex` — Template papan permainan
- `test/tic_tac_toe/game_test.exs` — Tes GenServer (12 tes)
- `test/tic_tac_toe_web/channels/game_channel_test.exs` — Tes channel/GenServer (4 tes)
- `test/tic_tac_toe_web/controllers/game_controller_test.exs` — Tes controller (1 tes)

### Diubah
- `lib/tic_tac_toe/application.ex` — Tambah `TicTacToe.Cluster` ke supervision tree
- `lib/tic_tac_toe_web/router.ex` — Tambah route `/game` dan channel `games:*`
- `lib/tic_tac_toe_web/endpoint.ex` — Tambah socket `/socket` untuk channel
- `lib/tic_tac_toe_web.ex` — Impor `channel/2` dari `Phoenix.Socket` di router
- `assets/js/app.js` — Expose `Phoenix.Socket` ke `window`
- `config/config.exs` — Tambah konfigurasi cluster (node_name, cookie, cluster_nodes)
- `config/runtime.exs` — Baca konfigurasi cluster dari env vars untuk release
- `config/dev.exs` — Bind ke `0.0.0.0` untuk akses LAN

## Catatan Penting
- `mix phx.server` cukup untuk development di satu host. Untuk distributed multi-host, pakai `mix release` dan jalankan di masing-masing host sebagai node Erlang terpisah.
- Host A dan Host B harus sama OS dan arsitektur (misalnya keduanya Linux x86_64 atau keduanya macOS ARM64) jika release dibuild di satu mesin dan disalin. Untuk cross-platform, build di masing-masing platform target.
- Tidak perlu install Elixir/Erlang di host target jika release sudah include ERTS.
- Jalankan setiap host sebagai node terpisah:
  - Host A: `TIC_TAC_TOE_NODE_NAME=tic@host-a TIC_TAC_TOE_COOKIE=rahasia TIC_TAC_TOE_CLUSTER_NODES=tic@host-b bin/tic_tac_toe start`
  - Host B: `TIC_TAC_TOE_NODE_NAME=tic@host-b TIC_TAC_TOE_COOKIE=rahasia TIC_TAC_TOE_CLUSTER_NODES=tic@host-a bin/tic_tac_toe start`
- Buka firewall: port EPMD (4369) dan port range distribusi Erlang.
- `PHX_SERVER=true` perlu diset saat menjalankan release agar endpoint menyala.
