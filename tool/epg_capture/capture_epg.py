#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""nasne EPG 採取スクリプト (torne mobile HB の BS 番組表ジャンル色検証 / CS 版数表の採取用).

アプリ (torne mobile HB) と同一の経路で nasne から番組表 (EPG) を取得し,
生データをファイルに保存する。あわせて, 取得できたイベントのうち
ジャンル情報 (ARIB STD-B10 content descriptor, タグ 0x54) を持つものの
数を数えて表示する。

検証の焦点は次の 2 点:
  1. nasne が配信する EPG ペイロードに content descriptor が残っているか
     (放送波の EIT にジャンルが含まれること自体は規格上確定している)
  2. アプリのパーサが BS (衛星) 経路でそれを拾える形で届いているか
     (セクションの table_id の内訳が手がかりになる)

あわせて, 版数表 (EPGVersionInfoGet の応答) はバイナリ全量をそのまま
保存する。衛星バンド (type 3) には BS と CS のサービスが混在するため,
CS が受信できる環境で実行すれば, CS の版数表に現れる flags の分布と
レコード長を確定させるためのフィクスチャとしても使える
(CS の番組表対応に必要)。

アプリの取得経路 (lib/core/services/epg.dart, plan 21/24 の実測形式):
  1. GET /status/networkIfInfoGet           -> MAC アドレス (トークン導出用)
  2. GET /status/channelListGet?broadcastingType=<t>
  3. GET /status/EPGVersionInfoGet?broadcastingType=<t>  (バイナリ版表)
  4. 版表からサービス一覧を作り, EPGGet リクエストボディを組み立てる
     (8 バイトヘッダ + サービス毎 24 バイト, 基本/拡張の全セグメント要求)
  5. POST /chEpg/EPGGet (Content-Type: application/binary,
     X-DTVToken = base64(SHA1(PIN + "/chEpg/EPGGet" + body 先頭 256 バイト)),
     PIN は MAC アドレスの下 3 オクテット)
  6. 応答は XOR 0x9d で難読化された zlib ストリーム。
     復号すると EIT セクションの連結になる

資格情報は扱わない。PIN は機体の MAC アドレスから導出される値で,
パスワードではない (アプリも登録済み機体の MAC からその都度導出する)。
すべての取得は読み取り専用で, 機体の設定は変更しない。

使い方:
  python3 capture_epg.py <nasne の IP> [--type 3] [--outdir epg_capture_out]

  --type は WebAPI の broadcastingType。3 = 衛星 (BS/CS), 2 = 地デジ。
  既定は 3 (衛星)。Python 3.8+ / 標準ライブラリのみ。
"""

import argparse
import base64
import hashlib
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import zlib
from datetime import datetime

PORT = 64210
XOR_KEY = 0x9D

# アプリ (lib/ui/epg_genre.dart) と同じ ARIB ジャンル大分類の表示名。
GENRE_LV1_LABELS = {
    0: "ニュース・報道",
    1: "スポーツ",
    2: "情報・ワイドショー",
    3: "ドラマ",
    4: "音楽",
    5: "バラエティ",
    6: "映画",
    7: "アニメ・特撮",
    8: "ドキュメンタリー・教養",
    9: "劇場・公演",
    10: "趣味・教育",
    11: "福祉",
    15: "その他",
}

VERSION_TABLE_HEADER = 12
VERSION_TABLE_RECORD = 144
EPG_GET_HEADER = 8
EPG_GET_RECORD = 24


def fail(message):
    print(f"エラー: {message}", file=sys.stderr)
    sys.exit(2)


def http_get(host, path, params=None, timeout=30):
    url = f"http://{host}:{PORT}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            return resp.read()
    except urllib.error.HTTPError as e:
        fail(f"GET {path} が HTTP {e.code} を返しました: "
             f"{e.read()[:200]!r}")
    except OSError as e:
        fail(f"GET {path} に失敗しました: {e}")


def http_post_binary(host, path, body, token, timeout=120):
    url = f"http://{host}:{PORT}{path}"
    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "Content-Type": "application/binary",
            "X-DTVToken": token,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read()
    except urllib.error.HTTPError as e:
        fail(f"POST {path} が HTTP {e.code} を返しました: "
             f"{e.read()[:200]!r}")
    except OSError as e:
        fail(f"POST {path} に失敗しました: {e}")


def u16be(b, off):
    return (b[off] << 8) | b[off + 1]


def bcd(v):
    return ((v >> 4) * 10) + (v & 0x0F)


# ---------------------------------------------------------------------------
# 版表 (EPGVersionInfoGet) の解析 — アプリ lib/core/parsing/epg.dart の移植
# ---------------------------------------------------------------------------

def parse_version_services_terrestrial(table):
    """地デジ: flags 0xc000 のレコードが続く間を列挙する。"""
    services = []
    offset = VERSION_TABLE_HEADER
    while offset + VERSION_TABLE_RECORD <= len(table):
        if u16be(table, offset + 6) != 0xC000:
            break
        services.append((
            u16be(table, offset),
            u16be(table, offset + 2),
            u16be(table, offset + 4),
        ))
        offset += VERSION_TABLE_RECORD
    return services


def parse_version_services_satellite(table, channels):
    """衛星: 版表の全スロットを走査し, チャンネル一覧の映像サービス
    (serviceType == 1) と三つ組みが一致するものだけを残す。"""
    known = {
        (c["networkId"], c["transportStreamId"], c["serviceId"])
        for c in channels if c.get("serviceType") == 1
    }
    seen = set()
    services = []
    p = VERSION_TABLE_HEADER
    while p + VERSION_TABLE_RECORD <= len(table):
        key = (
            u16be(table, p),
            u16be(table, p + 2),
            u16be(table, p + 4),
        )
        if key in known and key not in seen:
            seen.add(key)
            services.append(key)
        p += VERSION_TABLE_RECORD
    return services


def build_epg_get_body(services):
    """EPGGet リクエストボディ (アプリ buildEpgGetBody の移植)。
    基本・拡張の両ビットマップを全て立て, 全セグメントを要求する。"""
    out = bytearray(EPG_GET_HEADER + EPG_GET_RECORD * len(services))
    out[4] = (len(services) >> 8) & 0xFF
    out[5] = len(services) & 0xFF
    offset = EPG_GET_HEADER
    for network_id, tsid, service_id in services:
        out[offset] = (network_id >> 8) & 0xFF
        out[offset + 1] = network_id & 0xFF
        out[offset + 2] = (tsid >> 8) & 0xFF
        out[offset + 3] = tsid & 0xFF
        out[offset + 4] = (service_id >> 8) & 0xFF
        out[offset + 5] = service_id & 0xFF
        # +6: linked-description フラグ (アプリの既定は 0), +7: pad
        for i in range(offset + 8, offset + 24):
            out[i] = 0xFF
        offset += EPG_GET_RECORD
    return bytes(out)


def compute_token(pin, path, body):
    """X-DTVToken (アプリ lib/core/token.dart の移植)。"""
    digest = hashlib.sha1(
        pin.encode("utf-8") + path.encode("utf-8") + body[:256]
    ).digest()
    return base64.b64encode(digest).decode("ascii")


def derive_pin(mac_addr):
    """PIN は MAC アドレス (コロン除去) の 7 文字目以降 = 下 3 オクテット。
    表記は機体が返したままを使う (アプリ derivePin の移植)。"""
    stripped = mac_addr.replace(":", "")
    if len(stripped) < 12:
        fail(f"MAC アドレスの形式が想定と違います: {mac_addr!r}")
    return stripped[6:]


# ---------------------------------------------------------------------------
# EIT セクションの走査とイベント集計 — アプリの _findSections /
# _parseSectionEvents の、集計に必要な範囲の移植
# ---------------------------------------------------------------------------

def _make_crc_table():
    table = []
    for n in range(256):
        crc = n << 24
        for _ in range(8):
            crc = ((crc << 1) ^ 0x04C11DB7) & 0xFFFFFFFF \
                if crc & 0x80000000 else (crc << 1) & 0xFFFFFFFF
        table.append(crc)
    return table


_CRC_TABLE = _make_crc_table()


def crc32_mpeg(data, start, end):
    """CRC-32/MPEG-2。完結したセクション (CRC 込み) では 0 になる。"""
    crc = 0xFFFFFFFF
    for i in range(start, end):
        crc = ((crc << 8) & 0xFFFFFFFF) ^ _CRC_TABLE[((crc >> 24) ^ data[i]) & 0xFF]
    return crc


def table_class(table_id):
    if table_id in (0x4E, 0x4F):
        return "現在/次 (0x4e/0x4f)"
    if 0x50 <= table_id <= 0x57:
        return "基本 (0x50-0x57)"
    if 0x58 <= table_id <= 0x5F:
        return "拡張 (0x58-0x5f)"
    if 0x60 <= table_id <= 0x6F:
        return "他TS (0x60-0x6f)"
    return f"その他 (0x{table_id:02x})"


def find_sections(plain, channels, broadcasting_type):
    """アプリと同じアンカー方式: チャンネルの (tsid, onid) バイト列を
    探し, table_id / serviceId / 長さ / CRC で検証したものだけを拾う。"""
    found = {}  # offset -> (total_length, channel)
    for ch in channels:
        tsid = ch["transportStreamId"]
        onid = ch["networkId"]
        anchor = bytes([
            (tsid >> 8) & 0xFF, tsid & 0xFF,
            (onid >> 8) & 0xFF, onid & 0xFF,
        ])
        pos = 0
        while True:
            i = plain.find(anchor, pos)
            if i < 0:
                break
            pos = i + 1
            if i < 8:
                continue
            s = i - 8
            table_id = plain[s]
            is_eit = (
                table_id in (0x4E, 0x4F)
                or 0x50 <= table_id <= 0x5F
                or (broadcasting_type == 3 and 0x60 <= table_id <= 0x6F)
            )
            if not is_eit:
                continue
            if u16be(plain, s + 3) != ch["serviceId"]:
                continue
            total = (((plain[s + 1] & 0x0F) << 8) | plain[s + 2]) + 3
            if total < 18 or s + total > len(plain):
                continue
            if crc32_mpeg(plain, s, s + total) != 0:
                continue
            found[s] = (total, ch)
    return [(off, found[off][0], found[off][1]) for off in sorted(found)]


def parse_section_events(plain, start, end):
    """1 セクションのイベント列を読む。
    戻り値: (event_id, 開始キー, タイトル有無, ジャンル (lv1, lv2) or None)"""
    events = []
    p = start
    while p + 12 <= end:
        event_id = u16be(plain, p)
        mjd = u16be(plain, p + 2)
        start_key = (mjd, bcd(plain[p + 4]), bcd(plain[p + 5]),
                     bcd(plain[p + 6]))
        dlen = u16be(plain, p + 10) & 0x0FFF
        if p + 12 + dlen > end:
            break
        has_title = False
        genre = None
        q = p + 12
        dend = p + 12 + dlen
        while q + 2 <= dend:
            tag = plain[q]
            ln = plain[q + 1]
            if q + 2 + ln > dend:
                break
            body = plain[q + 2:q + 2 + ln]
            if tag == 0x4D:  # short_event_descriptor
                if len(body) >= 5 and body[0:3] == b"jpn":
                    has_title = True
            elif tag == 0x54:  # content_descriptor
                if len(body) >= 1 and genre is None:
                    genre = (body[0] >> 4, body[0] & 0x0F)
            q += 2 + ln
        events.append((event_id, start_key, has_title, genre))
        p += 12 + dlen
    return events


# ---------------------------------------------------------------------------
# 本体
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="nasne からアプリと同一経路で EPG を取得し, "
                    "ジャンル (content descriptor) の有無を集計する。"
                    "版数表などの生データ一式も保存する")
    parser.add_argument("host", help="nasne の IP アドレス (例: 192.168.1.10)")
    parser.add_argument("--type", type=int, default=3,
                        help="broadcastingType (3=衛星 BS/CS, 2=地デジ; 既定 3)")
    parser.add_argument("--outdir", default="epg_capture_out",
                        help="保存先フォルダ (既定 epg_capture_out)")
    args = parser.parse_args()
    host = args.host
    btype = args.type
    band = "衛星 (BS/CS)" if btype == 3 else \
        "地デジ" if btype == 2 else f"type={btype}"

    lines = []

    def out_line(text=""):
        print(text)
        lines.append(text)

    out_line(f"nasne EPG 採取: host={host} broadcastingType={btype} ({band})")
    out_line(f"実行日時: {datetime.now().astimezone().isoformat(timespec='seconds')}")
    out_line("")

    # 1. MAC アドレス -> PIN (トークン導出)
    net_info = json.loads(http_get(host, "/status/networkIfInfoGet")
                          .decode("utf-8"))
    mac = net_info.get("macAddr")
    if not mac:
        fail("networkIfInfoGet の応答に macAddr がありません")
    pin = derive_pin(mac)
    out_line(f"機体 MAC アドレス: {mac}")

    # 2. チャンネル一覧
    channels_raw = http_get(host, "/status/channelListGet",
                            {"broadcastingType": str(btype)})
    channels_doc = json.loads(channels_raw.decode("utf-8"))
    channels = channels_doc.get("channel") or []
    video_channels = [c for c in channels if c.get("serviceType") == 1]
    out_line(f"チャンネル一覧: {len(channels)} 件 "
             f"(映像サービス {len(video_channels)} 件)")

    # 3. 版表
    version_table = http_get(host, "/status/EPGVersionInfoGet",
                             {"broadcastingType": str(btype)})
    out_line(f"EPG 版表: {len(version_table)} バイト")

    # 4. サービス一覧 (バンドで解析方法が違う — アプリと同じ分岐)
    if btype == 3:
        services = parse_version_services_satellite(version_table, channels)
    else:
        services = parse_version_services_terrestrial(version_table)
    out_line(f"取得対象サービス: {len(services)} 件")
    if not services:
        fail("取得対象サービスが 0 件です。版表が空か, チャンネル一覧と"
             "一致しません (番組表データがまだ作られていない可能性があります)")

    # 5. EPGGet
    body = build_epg_get_body(services)
    token = compute_token(pin, "/chEpg/EPGGet", body)
    response_raw = http_post_binary(host, "/chEpg/EPGGet", body, token)
    out_line(f"EPGGet 応答 (生): {len(response_raw)} バイト")

    # 6. 復号: XOR 0x9d -> zlib
    deobfuscated = bytes(b ^ XOR_KEY for b in response_raw)
    try:
        plain = zlib.decompressobj().decompress(deobfuscated)
    except zlib.error as e:
        fail(f"応答の zlib 展開に失敗しました: {e}")
    out_line(f"復号後の EIT 連結: {len(plain)} バイト")
    out_line("")

    # 保存
    os.makedirs(args.outdir, exist_ok=True)
    saved = {}

    def save(name, data):
        path = os.path.join(args.outdir, name)
        with open(path, "wb") as f:
            f.write(data)
        saved[name] = len(data)

    save(f"channels_type{btype}.json", channels_raw)
    save(f"epg_version_table_type{btype}.bin", version_table)
    save(f"epg_get_request_type{btype}.bin", body)
    save(f"epg_get_response_type{btype}.raw", response_raw)
    save(f"epg_eit_type{btype}.bin", plain)

    # 7. セクション走査と集計 (アプリのパーサと同じアンカー方式)
    sections = find_sections(plain, channels, btype)
    class_counts = {}
    per_service = {}  # service triple -> {key: [has_title, genre]}
    for offset, total, ch in sections:
        cls = table_class(plain[offset])
        class_counts[cls] = class_counts.get(cls, 0) + 1
        triple = (ch["networkId"], ch["transportStreamId"], ch["serviceId"])
        merged = per_service.setdefault(triple, {})
        for event_id, start_key, has_title, genre in \
                parse_section_events(plain, offset + 14, offset + total - 4):
            key = (event_id, start_key)
            entry = merged.get(key)
            if entry is None:
                merged[key] = [has_title, genre]
            else:
                entry[0] = entry[0] or has_title
                if entry[1] is None:
                    entry[1] = genre

    out_line(f"検証を通った EIT セクション: {len(sections)} 件")
    for cls in sorted(class_counts):
        out_line(f"  {cls}: {class_counts[cls]} 件")
    out_line("")

    name_by_triple = {
        (c["networkId"], c["transportStreamId"], c["serviceId"]):
            c.get("serviceName") or ""
        for c in channels
    }
    total_events = 0
    total_genre = 0
    genre_hist = {}
    out_line("サービス別 (イベントは基本/拡張の複製を名寄せした一意な件数):")
    for triple in services:
        merged = per_service.get(triple, {})
        n = len(merged)
        n_title = sum(1 for v in merged.values() if v[0])
        n_genre = sum(1 for v in merged.values() if v[1] is not None)
        for v in merged.values():
            if v[1] is not None:
                genre_hist[v[1][0]] = genre_hist.get(v[1][0], 0) + 1
        total_events += n
        total_genre += n_genre
        name = name_by_triple.get(triple, "")
        out_line(f"  {name} (sid={triple[2]}): イベント {n} 件, "
                 f"タイトル有 {n_title} 件, ジャンル有 {n_genre} 件")
    out_line("")
    if total_events:
        pct = 100.0 * total_genre / total_events
        out_line(f"合計: イベント {total_events} 件, "
                 f"ジャンル (content descriptor) 有 {total_genre} 件 "
                 f"({pct:.1f}%)")
    else:
        out_line("合計: イベント 0 件")
    if genre_hist:
        out_line("ジャンル大分類の内訳:")
        for lv1 in sorted(genre_hist):
            label = GENRE_LV1_LABELS.get(lv1, "名称なし (予約/拡張)")
            out_line(f"  lv1={lv1} {label}: {genre_hist[lv1]} 件")
    out_line("")
    if total_events and total_genre == 0:
        out_line("一次判定: イベントは届いているがジャンルが 1 件も無い。"
                 "nasne のペイロードの段階で content descriptor が"
                 "落ちている可能性が高い。")
    elif total_genre:
        out_line("一次判定: nasne のペイロードに content descriptor が"
                 f"残っている。残る問題はアプリのパーサが {band} の経路で"
                 "拾えているかで, 保存した EIT バイナリで検証できる。")
    out_line("")
    out_line(f"保存ファイル ({args.outdir}/):")
    for name in sorted(saved):
        out_line(f"  {name}: {saved[name]} バイト")

    summary_path = os.path.join(args.outdir, f"summary_type{btype}.txt")
    with open(summary_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"サマリを {summary_path} に保存しました")


if __name__ == "__main__":
    main()
