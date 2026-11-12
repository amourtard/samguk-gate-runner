#!/usr/bin/env python3
"""플레이 기록 분석. 모은 사건으로 마크다운 보고서를 만든다.

쓰는 법
  서버에서 받아서:  python tools/analyze_logs.py --url https://<배포 주소> --token <EXPORT_TOKEN> --out 보고서.md
  받은 파일로:      python tools/analyze_logs.py --file events.jsonl --out 보고서.md
  원본도 남기려면:  --save events.jsonl (서버에서 받은 줄을 그대로 저장)

파일은 한 줄에 사건 하나인 JSON이다(게임의 로컬 기록 user://telemetry.jsonl과 같은 형식).
표준 라이브러리만 쓴다.
"""
import argparse
import collections
import json
import statistics
import sys
import urllib.parse
import urllib.request

PAGE = 5000


def fetch(url, token):
    """서버의 /api/export를 끝까지 넘겨 가며 받는다."""
    rows, after = [], 0
    while True:
        query = urllib.parse.urlencode({"token": token, "after": after, "limit": PAGE})
        with urllib.request.urlopen(f"{url.rstrip('/')}/api/export?{query}", timeout=60) as response:
            page = json.load(response)
        rows.extend(page["rows"])
        if not page.get("next"):
            return rows
        after = page["next"]


def normalize(row):
    """서버 줄과 로컬 파일 줄을 같은 모양으로 맞춘다."""
    data = row.get("data") or {}
    if isinstance(data, str):
        data = json.loads(data)
    return {
        "time": int(row.get("client_time") or row.get("time") or 0),
        "player": row.get("player", ""),
        "session": row.get("session", ""),
        "run": row.get("run") or "",
        "type": row.get("type", ""),
        "stage": row.get("stage") or "",
        "hero": row.get("hero") or "",
        "build": row.get("build") or "",
        "data": data,
    }


def median(values):
    return statistics.median(values) if values else 0


def percent(part, whole):
    return f"{100 * part / whole:.0f}%" if whole else "-"


def table(header, rows):
    lines = ["| " + " | ".join(header) + " |", "| " + " | ".join("---" for _ in header) + " |"]
    lines += ["| " + " | ".join(str(cell) for cell in row) + " |" for row in rows]
    return "\n".join(lines) + "\n"


def report(events, build=None):
    if build:
        events = [e for e in events if e["build"] == build]
    events.sort(key=lambda e: e["time"])
    by_type = collections.defaultdict(list)
    for event in events:
        by_type[event["type"]].append(event)
    starts = {e["run"]: e for e in by_type["run_start"]}
    ends = {e["run"]: e for e in by_type["run_end"]}
    out = ["# 플레이 기록 분석\n"]
    builds = sorted({e["build"] for e in events})
    players = {e["player"] for e in events}
    out.append(f"- 빌드: {', '.join(builds) or '-'}\n- 사건 {len(events)}개, 사람(기기) {len(players)}명, 실행 {len({e['session'] for e in events})}번, 판 {len(starts)}개\n")

    # 1. 사람당 판 수: 30판을 채우는 사람이 있는가
    runs_by_player = collections.Counter(e["player"] for e in by_type["run_start"])
    counts = sorted(runs_by_player.values(), reverse=True)
    out.append("## 사람당 판 수\n")
    out.append(f"- 중앙값 {median(counts)}판, 최대 {counts[0] if counts else 0}판\n")
    buckets = [("1판", 1, 1), ("2~4판", 2, 4), ("5~9판", 5, 9), ("10~29판", 10, 29), ("30판 이상", 30, 10 ** 9)]
    out.append(table(["판 수", "사람"], [[name, sum(1 for c in counts if low <= c <= high)] for name, low, high in buckets]))

    # 2. 끝나지 않은 판(중간에 나감)
    unfinished = [run for run in starts if run not in ends]
    out.append("## 끝까지 가지 않은 판\n")
    out.append(f"- 시작 {len(starts)}판 중 끝 기록이 없는 판 {len(unfinished)}판 ({percent(len(unfinished), len(starts))}). 중간에 창을 닫았거나 기록이 오지 않은 판이다.\n")

    # 3. 스테이지, 장수별 돌파율
    out.append("## 스테이지와 장수별 돌파율\n")
    grid = collections.defaultdict(lambda: [0, 0])
    for run, end in ends.items():
        for key in [(end["stage"], end["hero"]), (end["stage"], "전체")]:
            grid[key][0] += 1 if end["data"].get("cleared") else 0
            grid[key][1] += 1
    heroes = sorted({hero for _, hero in grid if hero != "전체"}) + ["전체"]
    stages = sorted({stage for stage, _ in grid}, key=lambda s: [int(p) if p.isdigit() else 0 for p in s.split("-")])
    out.append(table(["스테이지"] + heroes, [[stage] + [f"{grid[(stage, h)][0]}/{grid[(stage, h)][1]} ({percent(*grid[(stage, h)])})" if grid[(stage, h)][1] else "-" for h in heroes] for stage in stages]))

    # 4. 진 판이 끝난 구간
    out.append("## 진 판이 끝난 구간\n")
    lost = collections.Counter()
    for end in ends.values():
        if not end["data"].get("cleared"):
            section, sections = end["data"].get("section", 0), end["data"].get("sections", 0)
            lost[(end["stage"], "보스전" if section > sections else f"구간 {section}")] += 1
    out.append(table(["스테이지", "끝난 곳", "판"], [[stage, where, n] for (stage, where), n in sorted(lost.items())]))

    # 5. 판 길이
    out.append("## 판 길이(초)\n")
    lengths = collections.defaultdict(list)
    for end in ends.values():
        lengths[(end["stage"], "돌파" if end["data"].get("cleared") else "패배")].append(end["data"].get("seconds", 0))
    out.append(table(["스테이지", "결과", "판", "중앙값", "최소", "최대"], [[stage, result, len(v), f"{median(v):.0f}", f"{min(v):.0f}", f"{max(v):.0f}"] for (stage, result), v in sorted(lengths.items())]))

    # 6. 책략: 나왔을 때 고른 비율, 가진 판의 돌파율
    out.append("## 책략\n")
    offered, chosen = collections.Counter(), collections.Counter()
    for event in by_type["strategy_pick"]:
        for name in event["data"].get("offer", []):
            offered[name] += 1
        chosen[event["data"].get("chosen", "")] += 1
    owned = collections.defaultdict(lambda: [0, 0])
    for end in ends.values():
        for name in set(end["data"].get("strategies", [])):
            owned[name][0] += 1 if end["data"].get("cleared") else 0
            owned[name][1] += 1
    out.append(table(["책략", "나온 횟수", "고른 횟수", "고른 비율", "가진 판의 돌파율"], [[name, offered[name], chosen[name], percent(chosen[name], offered[name]), f"{owned[name][0]}/{owned[name][1]} ({percent(*owned[name])})"] for name in sorted(offered, key=lambda n: -chosen[n])]))

    # 7. 게이트: 종류별로 골라진 비율(그 종류가 한쪽에 나왔을 때)
    out.append("## 게이트\n")
    shown, picked, change = collections.Counter(), collections.Counter(), collections.defaultdict(list)
    for event in by_type["gate"]:
        data = event["data"]
        kinds = [str(data.get("chosen", "")).split(":")[0], str(data.get("other", "")).split(":")[0]]
        for kind in set(kinds):
            shown[kind] += 1
        picked[kinds[0]] += 1
        change[str(data.get("chosen", ""))].append(data.get("after", 0) - data.get("before", 0))
    out.append(table(["종류", "나온 횟수", "고른 횟수", "고른 비율"], [[kind, shown[kind], picked[kind], percent(picked[kind], shown[kind])] for kind in sorted(shown, key=lambda k: -shown[k])]))
    out.append("고른 칸별 병력 변화(중앙값)\n\n")
    out.append(table(["칸", "고른 횟수", "병력 변화 중앙값"], [[name, len(v), f"{median(v):+.0f}"] for name, v in sorted(change.items(), key=lambda item: -len(item[1]))]))

    # 8. 일반 교전: 너무 짧지 않은가
    out.append("## 적 무리 교전\n")
    fights = collections.defaultdict(list)
    for event in by_type["group_end"]:
        fights[(event["stage"], event["data"].get("section", 0))].append(event["data"])
    rows = []
    for (stage, section), items in sorted(fights.items()):
        contact = [d["contact_seconds"] for d in items if d.get("contact_seconds", -1) >= 0]
        loss = [d.get("before", 0) - d.get("after", 0) for d in items]
        rows.append([stage, section, len(items), f"{median([d.get('enemies', 0) for d in items]):.0f}", f"{median(contact):.1f}" if contact else "-", percent(len(items) - len(contact), len(items)), f"{median(loss):.0f}"])
    out.append(table(["스테이지", "구간", "무리 수", "적 수 중앙값", "접촉 후 걸린 시간 중앙값(초)", "닿기 전에 잡은 비율", "잃은 병력 중앙값"], rows))

    # 9. 보스전
    out.append("## 보스전\n")
    boss = collections.defaultdict(list)
    for event in by_type["boss_end"]:
        boss[(event["stage"], event["hero"])].append(event["data"])
    rows = []
    for (stage, hero), items in sorted(boss.items()):
        zones, zone_hits = sum(d.get("zones", 0) for d in items), sum(d.get("zone_hits", 0) for d in items)
        balls, ball_hits = sum(d.get("fireballs", 0) for d in items), sum(d.get("fireball_hits", 0) for d in items)
        rows.append([stage, hero, len(items), percent(sum(1 for d in items if d.get("cleared")), len(items)), f"{median([d.get('count_start', 0) for d in items]):.0f}", f"{median([d.get('seconds', 0) for d in items]):.0f}", percent(zone_hits, zones), percent(ball_hits, balls)])
    out.append(table(["스테이지", "장수", "보스전 수", "승률", "도달 병력 중앙값", "길이 중앙값(초)", "구역 공격에 맞은 비율", "불덩이에 맞은 비율"], rows))

    # 10. 결과 화면에서 누른 버튼, 강화
    out.append("## 결과 화면에서 누른 버튼\n")
    actions = collections.Counter(e["data"].get("action", "") for e in by_type["result_action"])
    out.append(table(["버튼", "횟수"], sorted(actions.items(), key=lambda item: -item[1])))
    out.append("## 강화 구매\n")
    upgrades = collections.Counter(e["data"].get("id", "") for e in by_type["upgrade_buy"])
    out.append(table(["시설", "횟수"], sorted(upgrades.items(), key=lambda item: -item[1])))
    return "\n".join(out)


def main():
    parser = argparse.ArgumentParser(description="플레이 기록 분석 보고서를 만든다")
    parser.add_argument("--url", help="배포 주소(예: https://example.vercel.app)")
    parser.add_argument("--token", help="EXPORT_TOKEN")
    parser.add_argument("--file", help="한 줄에 사건 하나인 JSON 파일")
    parser.add_argument("--save", help="서버에서 받은 줄을 이 파일에 저장")
    parser.add_argument("--build", help="이 빌드의 기록만 본다")
    parser.add_argument("--out", help="보고서를 쓸 파일(없으면 화면에 출력)")
    args = parser.parse_args()
    if args.file:
        with open(args.file, encoding="utf-8") as handle:
            rows = [json.loads(line) for line in handle if line.strip()]
    elif args.url and args.token:
        rows = fetch(args.url, args.token)
        if args.save:
            with open(args.save, "w", encoding="utf-8") as handle:
                for row in rows:
                    handle.write(json.dumps(row, ensure_ascii=False) + "\n")
    else:
        parser.error("--file 또는 --url과 --token이 필요합니다")
    text = report([normalize(row) for row in rows], args.build)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as handle:
            handle.write(text)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
