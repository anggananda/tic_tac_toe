# Dokumentasi Arsitektur & Alur Aplikasi Tic-Tac-Toe (Elixir + Phoenix)

Dokumen ini menjelaskan bagaimana aplikasi tic-tac-toe ini bekerja, dari yang paling dasar (bagaimana Phoenix menangani HTTP request) sampai yang teknis (bagaimana permainan real-time berjalan lintas host melalui Erlang distribution dan Phoenix Channels/PubSub).

Ditulis untuk: developer baru yang ingin memahami basis kode ini, dan tim yang akan mengembangkan atau men-deploy aplikasi ke beberapa host.

---

## 1. Ringkasan Singkat

Aplikasi ini adalah permainan tic-tac-toe (3x3) yang:

- Dilayani oleh **Phoenix web framework** di atas **Elixir/Erlang**.
- Halaman utama (`/`) berfungsi sebagai **landing page** full height tanpa scroll.
- Halaman permainan (`/game`) menampilkan papan 3x3 yang bisa diklik.
- Gerakan pemain disinkronkan **real-time** ke lawan melalui **WebSocket (Phoenix Channels)**.
- State permainan disimpan dalam satu **GenServer** (`TicTacToe.Game`) yang terdaftar secara global (`:global`), sehingga siap untuk dijalankan di **beberapa host (distributed)** dengan Erlang node distribution.

---

## 2. Dasar Phoenix (Dari Paling Dasar)

### 2.1 Apa itu Phoenix?

Phoenix adalah framework web untuk Elixir yang berjalan di BEAM (Erlang VM). Keunggulannya:

- **Concurrency tinggi**: ribuan koneksi WebSocket bisa ditangani sekaligus dengan biaya rendah (proses Elixir ringan).
- **Fault tolerant**: jika satu proses error, proses lain tidak ikut mati (supervision tree).
- **Real-time bawaan**: Phoenix Channels untuk WebSocket, PubSub untuk broadcast.

### 2.2 Alur Request HTTP (Tanpa WebSocket)

Ketika pengguna membuka `http://localhost:4000/`, alurnya adalah:

```
Browser
  │
  ▼
Cowboy (HTTP server bawaan Erlang)
  │
  ▼
Endpoint (TicTacToeWeb.Endpoint) — titik masuk semua request
  │
  ▼
Router (TicTacToeWeb.Router) — mencocokkan path dengan controller
  │
  ▼
Pipeline :browser (plug: accepts, fetch_session, csrf protection, dll.)
  │
  ▼
Controller (PageController atau GameController)
  │
  ▼
Render template HEEx (.html.heex) melalui Layouts.app
  │
  ▼
HTML dikembalikan ke browser
```

### 2.3 Komponen Utama dalam Folder `lib/`

| File | Peran |
|------|-------|
| `lib/tic_tac_toe/application.ex` | Supervision tree: memulai proses-proses penting saat aplikasi nyala (GenServer game, cluster, PubSub). |
| `lib/tic_tac_toe/game.ex` | GenServer yang menyimpan state papan, giliran, dan pemenang. |
| `lib/tic_tac_toe/cluster.ex` | Koneksi Erlang node distribution antar host. |
| `lib/tic_tac_toe_web/endpoint.ex` | Titik masuk HTTP dan WebSocket. |
| `lib/tic_tac_toe_web/router.ex` | Routing: `GET /`, `GET /game`, `channel "games:*"`. |
| `lib/tic_tac_toe_web/controllers/page_controller.ex` | Mengatur halaman `/` (landing page). |
| `lib/tic_tac_toe_web/controllers/game_controller.ex` | Mengatur halaman `/game`. |
| `lib/tic_tac_toe_web/controllers/game_html.ex` | Helper view untuk game (`cell_symbol`, `cell_disabled?`). |
| `lib/tic_tac_toe_web/channels/game_channel.ex` | Phoenix Channel: handle `join`, `make_move`, `reset_game`. |
| `lib/tic_tac_toe_web/components/layouts.ex` | Layout aplikasi (`Layouts.app`) yang membungkus semua halaman. |
| `lib/tic_tac_toe_web/user_socket.ex` | UserSocket: otentikasi dan topik channel yang diizinkan. |

---

## 3. Alur Halaman Utama (`/`) — Landing Page

### 3.1 Router

Di `router.ex`:

```elixir
scope "/", TicTacToeWeb do
  pipe_through :browser
  get "/", PageController, :home
  get "/game", GameController, :index
end
```

`GET /` diproses oleh `PageController.home/2`, yang merender `page_html/home.html.heex`.

### 3.2 Layout (Wrapper Semua Halaman)

Setiap halaman dibungkus oleh `Layouts.app/1` di `layouts.ex`. Layout baru yang kita terapkan:

```elixir
<div class="flex flex-col min-h-screen bg-base-100 text-base-content">
  <header>...</header>          <!-- Navbar shrink-0, tidak ikut scroll -->
  <main class="flex-1 min-h-0 overflow-hidden">...</main> <!-- Konten penuh tinggi -->
  <.flash_group flash={@flash} />
</div>
```

Kunci-nya:
- `min-h-screen` → tinggi layar penuh (viewport).
- `flex-col` + `flex-1` pada `<main>` → konten mengisi sisa ruang, header tetap di atas.
- `overflow-hidden` → mencegah scroll di luar area yang diinginkan.
- Tidak ada `py-20` besar-besaran seperti default Phoenix, sehingga tampilan tidak kaku dan memenuhi layar.

### 3.3 Template Landing Page

`page_html/home.html.heex` berisi:

- Header dengan logo "Tic Tac Toe" dan tombol **Mulai Bermain** (`/game`) + theme toggle.
- Main area di tengah layar (`flex items-center justify-center`), text-center.
- Judul besar, deskripsi singkat, dua tombol CTA.
- Preview papan 3x3 sebagai dekorasi visual.
- `overflow-hidden` pada root div → **tidak ada scroll** apa pun.

---

## 4. Alur Halaman Permainan (`/game`)

### 4.1 Controller

`GameController.index/2`:

```elixir
def index(conn, _params) do
  state = TicTacToe.Game.get_state()
  render(conn, :index, board: state.board)
end
```

Mengambil board saat ini dari GenServer dan melewakkannya ke template.

### 4.2 Template Game

`game_html/index.html.heex` memanggil `<Layouts.app flash={@flash}>` dan menampilkan:

- Indikator giliran (`turn-indicator`).
- Pesan status (`status-message`).
- Papan 3x3: 9 tombol (`button[data-cell]`), masing-masing mewakili sel 0–8.
- Tombol **Ulangi Permainan** (`reset-button`).
- Script inline yang menginisialisasi Phoenix Channel (lihat bagian 6).

Styling:
- `rounded-2xl`, `bg-base-200`, hover `bg-base-300`, transisi halus (`active:scale-95`).
- Sel yang menang mendapatkan kelas `win` (bayangan hijau halus).
- Ukuran papan responsif (`300px` default, `380px` di layar besar).
- Semua dalam satu layar tanpa scroll berkat layout `flex-1` dan `min-h-0`.

---

## 5. State Permainan: GenServer (`TicTacToe.Game`)

Ini adalah "otak" permainan. Sebuah **GenServer** adalah proses Elixir yang menyimpan state dan menangani pesan secara berurutan (tidak perlu lock karena satu proses satu waktu).

### 5.1 State Default

```elixir
%{
  board: List.duplicate(nil, 9),   # 9 sel kosong
  players: %{x: nil, o: nil},      # PID pemain X dan O
  turn: :x,                        # Giliran siapa
  winner: nil,                     # nil, :x, :o, atau :draw
  game_id: "default"
}
```

### 5.2 Operasi Publik

| Fungsi | Aksi |
|--------|------|
| `start_link/0` | Memulai GenServer dan mendaftarkannya di `:global` sebagai `:tic_tac_toe_game`. |
| `get_state/0` | Mengembalikan state penuh (digunakan controller untuk render awal). |
| `join/0` | Mendaftarkan pemanggil sebagai pemain `:x` atau `:o`. Mengembalikan `{:ok, symbol}`. |
| `make_move/2` | Memvalidasi dan menempatkan simbol di papan, lalu menentukan giliran berikutnya dan pemenang. |
| `reset/1` | Mengembalikan state ke default. |

### 5.3 Validasi Gerakan (internal)

Sebelum menerima gerakan, GenServer memeriksa secara berurutan (`with`):

1. `validate_player/1` — simbol pemain harus sudah bergabung (`join`).
2. `validate_turn/1` — harus giliran pemain tersebut.
3. `validate_cell/1` — sel harus kosong.
4. `validate_game_active/1` — permainan belum selesai.

Kalau semua lolos, papan diperbarui, pemenang dicek, dan hasilnya disiarkan melalui PubSub (lihat bagian 6).

### 5.4 Pemeriksa Pemenang

Delapan garis menang (3 baris, 3 kolom, 2 diagonal). Jika ketiga sel dalam satu garis sama dan tidak kosong, ada pemenang. Jika papan penuh tanpa pemenang → `:draw`.

---

## 6. Real-Time dengan Phoenix Channels

Ini adalah bagian yang membuat gerakan muncul di lawan secara instan tanpa refresh halaman.

### 6.1 Socket & Channel

- `user_socket.ex`: mendefinisikan `channel "games:*", GameChannel`.
- `endpoint.ex`: mengekspos WebSocket di `/socket`.
- `router.ex`: `channel "games:*", TicTacToeWeb.GameChannel`.

### 6.2 Alur WebSocket di Browser (`app.js` + inline script)

`assets/js/app.js` mengekspos `Phoenix.Socket` ke `window` agar template game bisa menggunakannya tanpa import modul terpisah.

Di `game_html/index.html.heex`, script inline:

1. Buat `new window.Phoenix.Socket("/socket")` lalu `socket.connect()`.
2. Gabung channel: `socket.channel("games:default", {})` → `channel.join()`.
3. Server (`GameChannel.join`) memanggil `TicTacToe.Game.join()` dan menanggali simbol `:x` atau `:o`.
4. Browser menerima `{:ok, symbol}` dan menampilkan giliran awal.

### 6.3 Kirim Gerakan (`make_move`)

Ketika pengguna klik sel:

```javascript
channel.push("make_move", {position: cell})
```

Di server (`GameChannel.handle_in/3`):

```elixir
def handle_in("make_move", %{"position" => position}, socket) do
  symbol = socket.assigns.symbol
  case TicTacToe.Game.make_move(symbol, position) do
    {:ok, _state} -> {:noreply, socket}   # Berhasil, state sudah disiarkan lewat GenServer
    {:error, reason} -> {:reply, {:error, %{reason: reason}}, socket}
  end
end
```

### 6.4 Broadcast ke Semua Pemain

Saat `make_move` berhasil di GenServer, fungsi `broadcast_move/2` memanggil:

```elixir
Phoenix.PubSub.broadcast(TicTacToe.PubSub, "games:default", %{
  event: "game_move",
  board: state.board,
  turn: state.turn,
  winner: state.winner,
  last_move: %{symbol: symbol, position: position}
})
```

`GameChannel.handle_info/2` menangkap pesan PubSub ini dan mendorongnya ke semua klien yang subscribe topik `games:default`:

```elixir
def handle_info(%{event: "game_move"} = message, socket) do
  push(socket, "game_move", message)
  {:noreply, socket}
end
```

Browser menerima event `game_move`, lalu:
- Menggambar ulang papan (`renderBoard`).
- Memperbarui indikator giliran.
- Memperbarui pesan status.
- Jika ada pemenang, highlight sel-sel yang menang dan nonaktifkan papan.

### 6.5 Reset Permainan

Tombol "Ulangi Permainan" mendorong `reset_game` → `GameChannel.handle_in/3` memanggil `TicTacToe.Game.reset()` dan broadcast `game_reset` ke semua klien.

---

## 7. Distribusi Antar Host (Multi-Node)

Ini adalah daya tarik utama aplikasi: dua host berbeda bisa main satu pertandingan secara real-time.

### 7.1 Erlang Node Distribution

BEAM memungkinkan beberapa node (instansi Erlang VM) di host berbeda saling berbicara melalui TCP, asalkan:

- Mempunyai **node name** unik (misal `tic@host-a`, `tic@host-b`).
- Mempunyai **`.erlang.cookie`** yang sama (untuk autentikasi antar node).
- Terhubung via `Node.connect/1` (diatur oleh `TicTacToe.Cluster`).
- Firewall membuka port EPMD (4369) dan port range distribusi Erlang.

### 7.2 GenServer Global

`TicTacToe.Game` didaftarkan dengan:

```elixir
GenServer.start_link(__MODULE__, %{name: :game_server}, name: {:global, :tic_tac_toe_game})
```

Karena nama `:global`, GenServer ini bisa diakses dari **manapun dalam klaster** menggunakan `GenServer.call({:global, :tic_tac_toe_game}, ...)`. Jadi tidak importa di host mana GenServer dijalankan; semua node melihat satu state permainan yang sama.

### 7.3 Phoenix PubSub Terdistribusi

`Phoenix.PubSub.broadcast/3` mengirim pesan ke topik. Saat nodes terhubung via Erlang distribution, pesan PubSub secara otomatis melintasi node. Alur lengkap:

```
Pemain di Host A klik sel
  │
  ▼
WebSocket → Endpoint Host A → GameChannel di Host A
  │
  ▼
TicTacToe.Game.make_move/2 (GenServer, bisa di Host A atau B)
  │
  ▼
Phoenix.PubSub.broadcast("games:default", ...)
  │
  ▼
Diterima semua node yang terhubung (Host A dan Host B)
  │
  ▼
GameChannel di masing-masing host push "game_move" ke WebSocket miliknya
  │
  ▼
Browser lawan di Host B memperbarui papan secara real-time
```

### 7.4 Deploy dengan Release

Untuk production/distributed, pakai `mix release` (sudah termasuk ERTS, jadi target tidak perlu install Elixir/Erlang):

```bash
# Host A
TIC_TAC_TOE_NODE_NAME=tic@host-a \
TIC_TAC_TOE_COOKIE=rahasia \
TIC_TAC_TOE_CLUSTER_NODES=tic@host-b \
PHX_SERVER=true bin/tic_tac_toe start

# Host B
TIC_TAC_TOE_NODE_NAME=tic@host-b \
TIC_TAC_TOE_COOKIE=rahasia \
TIC_TAC_TOE_CLUSTER_NODES=tic@host-a \
PHX_SERVER=true bin/tic_tac_toe start
```

Lihat file `docs/2026-11-08-tic-tac-toe-distributed.md` untuk rencana implementasi distribusi dan checklist langkah demi langkah.

---

## 8. Struktur Folder (Singkat)

```
lib/
  tic_tac_toe/
    application.ex      # Supervision tree
    cluster.ex          # Koneksi node Erlang
    game.ex             # GenServer state permainan
    mailer.ex
    cluster.ex
  tic_tac_toe_web/
    controllers/
      page_controller.ex       # Halaman /
      game_controller.ex       # Halaman /game
      page_html/home.html.heex # Landing page
      game_html/index.html.heex # Papan permainan
      game_html.ex             # Helper view game
    channels/game_channel.ex   # WebSocket channel
    components/layouts.ex      # Layout aplikasi (Layouts.app)
    components/core_components.ex # Komponen UI bawaan Phoenix
    components/layouts/root.html.heex # Skeleton HTML
    endpoint.ex                # Titik masuk HTTP/WebSocket
    router.ex                  # Routing
    user_socket.ex             # Socket & otorisasi channel
    web.ex                     # Definisi alias & helper
assets/
  css/app.css                  # Tailwind + gaya kustom tic-tac-toe
  js/app.js                    # LiveSocket + expose Phoenix.Socket
config/
  config.exs, dev.exs, runtime.exs, test.exs
test/
  ... (tes controller, channel, GenServer)
docs/
  2026-11-08-tic-tac-toe-distributed.md   # Rencana distribusi
  2026-11-08-arsitektur-dan-alur-aplikasi.md # Dokumen ini
```

---

## 9. Keputusan UI/UX (Terbaru)

- **Full height, tidak ada scroll**: root container pakai `min-h-screen` dan `overflow-hidden`; `<main>` pakai `flex-1 min-h-0 overflow-hidden`.
- **Landing page sebagai `/`**: pengguna langsung melihat merk dan CTA "Mulai Bermain" di halaman utama.
- **Minimalis & tidak kaku**: hapus padding besar default Phoenix, pakai rounded corner besar (`rounded-2xl`), bayangan halus, transisi cepat (`duration-150`), dan warna X/O yang kontras namun lembut.
- **Feedback visual**: indikator giliran berwarna (X = primary, O = accent), sel menang di-highlight dengan bayangan hijau, pesan status selalu terlihat.
- **Tidak ada library CSS eksternal selain Tailwind + daisyUI yang sudah ada**, semua gaya ditulis manual dengan utility class.

---

## 10. Dari Klik sampai Muncul di Lawan (Ringkasan Akhir)

```
1. Pengguna klik sel di browser (Host A)
   │
2. Inline JS mendeteksi klik → channel.push("make_move", {position: 4})
   │
3. WebSocket ke Phoenix Endpoint (Host A) → GameChannel.handle_in("make_move")
   │
4. GameChannel panggil TicTacToe.Game.make_move(:x, 4)
   │
5. GenServer validasi → update board → cek pemenang → broadcast via PubSub
   │
6. PubSub menyebar ke semua node klaster (Host A dan Host B)
   │
7. GameChannel di setiap host push "game_move" ke WebSocket kliennya
   │
8. Browser lawan (Host B) menerima JSON → render ulang papan + status
```

Semua ini terjadi dalam hitungan milidetik, tanpa reload halaman, dan bekerja sama baik di satu host maupun beberapa host yang terhubung melalui Erlang distribution.
