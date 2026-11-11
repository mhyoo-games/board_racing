# 이 저장소에서 작업할 때 지킬 것

유민혁(minhyuk94)의 개인 프로젝트 "바람보드 레이싱". 사용자는 한국어로 대화합니다. 게임 글자도 한국어.

## 무엇인가

하늘을 나는 보드 3D 레이싱 (개인전·팀전 4:4·타임어택 메달·친구와 온라인 최대 8명, 스피드전/아이템전, 보드 상점·레벨·행운 상자, 트랙 5개). 점프대에서 A로 뛰고 공중에서 S(GB)·D(360)·F(720) 묘기, 판정 GOOD·NICE·EXCELLENT. 위에서 비스듬히 내려다보는 카메라.
Godot 4.6(GDScript, GL Compatibility), 웹으로 내보내 GitHub Pages(`https://mhyoo-games.github.io/board_racing/`, 조직 mhyoo-games)에 올린다.

## 지킬 것

- 라이선스 화면: `scripts/licenses.gd`가 Godot 엔진(MIT)과 그 안의 라이브러리(`Engine.get_license_text/get_copyright_info/get_license_info`), 갈무리 글꼴 전문(`assets/fonts/OFL.txt`, 내보내기 `include_filter`에 넣음), 그림 출처를 보여 준다. 처음 화면에서 연다. 상업·무료 상관없이 Godot 배포 조건이라 지우지 않는다. 새 에셋을 쓰면 여기 `credits`에도 적는다.
- 옛 온라인 보드 레이싱에서 영감을 받았지만 **새로 만든 게임**이다. 다른 게임의 이름·캐릭터·보드·트랙·그림·음악을 쓰지 않고, 다른 회사·게임 이름을 README·화면·이력서에 넣지 않는다. 판정 단어(GOOD·NICE·EXCELLENT)·묘기 이름(GB·360·720)은 흔한 말이라 쓴다.
- 그림: Kenney Platformer Kit(CC0, `assets/kit/LICENSE.txt`) — 캐릭터 5명(`character-*.glb`, 동작 idle·jump·fall·crouch·emote-yes), 나무·울타리·동전·꾸밈. 보드·길·점프대·계단·아치·탑·출발 문은 코드로 만든다(`scripts/board.gd`, `scripts/track_view.gd`). 글꼴: 갈무리(OFL).
- 소리: `tools/sound/gen.py`가 표준 라이브러리로 합성 → `assets/sfx`, `assets/music` (곡 title·race·sky·rush). 결과 wav를 직접 고치지 말고 생성기를 고친다. 소리는 QOA로 압축되므로 반복 끝은 `get_length() × mix_rate`. 아이콘은 `tools/art/icon.py`.
- 규칙(계산)은 `scripts/rules.gd`에 화면과 떨어뜨려 모은다: 보드 움직임(좌표 `Vector2(x, z)`, yaw 0 = +z, 오른쪽 핸들 = yaw 감소, 속도는 크기와 방향으로 나누고 방향은 접지력만큼 코를 따라감), 높이(`alt` 월드 높이, 땅은 `ground_at`이 줌: 점프대 오르막 `RAMP_H`·계단·얼음·낭떠러지 `gap`(h=-20)·발판 `pad`), 점프(땅 `HOP`, 점프대는 `ramp_judge`로 판정 → `JUMP_MULT`), 묘기(`TRICKS` 걸리는 시간·점수·도는 바퀴, 착지 때 덜 끝났으면 MISS + `STUMBLE_TIME`, 다 끝났으면 `land_judge(끝나고 남은 시간)`), 게이지(묘기 `TRICK_GAUGE`×점수×판정 배율×콤보×`gauge_gain`, 슬라이드 `SLIDE_GAUGE`), 부스터 두 개, 순위, 레이싱 라인, 컴퓨터 입력(점프대에서 정한 자리에 뛰고, 남은 공중 시간에 맞는 가장 큰 묘기를 끝나자마자 닿게), 보상·경험치·레벨·팀 점수·메달·행운 상자·상점·저장. 새 규칙에는 `tests/run_tests.gd`에 테스트를 더한다.
- 트랙은 `data/tracks.json`(조절점 [x, z] 또는 [x, z, 높이]·폭·`theme` grass/snow/sky/forest/castle·`music`·`par` 금메달 기록·`zones`). 구간은 길이 비율: ramp·pad는 `at`(끝 자리), stairs·ice는 `from`·`to`, gap은 `at` + `len`(미터). 낭떠러지 바로 앞은 꼭 점프대. 트랙을 바꾸면 테스트(컴퓨터가 다 도는지, 잘하는 컴퓨터는 거의 안 떨어지는지, 출발 자리가 평평한 길인지)가 통과해야 한다. `sky` 테마는 땅이 없고 길 가장자리가 난간.
- 보드는 `data/boards.json`(능력치 1~10, 상점 보드는 값 순서, `level` 살 수 있는 레벨, `rare`는 행운 상자에서만, `look` 모양·색). 캐릭터는 같은 파일 `riders`.
- 컴퓨터 상대는 사람 보드의 능력치를 기준으로 달린다(`Rules.ai_stats`) — 보드 종류는 겉모양만. 너무 어렵지 않게.
- 저장은 `user://board_racing_save.json` 하나 (`Rules.parse_save`가 망가진 값도 받아 준다).
- 카메라(`race._cameras`): 높이 떠서 비스듬히 내려다보고, 길 방향을 부드럽게 따라 돈다. 공중이면 땅 높이 쪽을 따라가 화면이 덜 흔들린다.
- Godot 4.6은 Variant에서 `:=`로 타입을 추론하면 오류다. 딕셔너리 값은 `var x: float = d.y`처럼 타입을 적는다. `Basis(...).scaled(v)`는 바깥 기준 크기라 돌린 상자를 늘릴 때는 `Basis(UP, yaw) * Basis.from_scale(v)`.
- 아이템전(`scripts/race_items.gd`, 규칙은 `Rules.item_roll/give_item/hit/ai_use_item`): 상자 5줄×6개(구간을 피해 둠), 아이템 두 칸, Space로 사용, 공중에 높이 떠 있으면 바닥 끈끈이를 피함. 온라인은 스피드전(팀전 가능).
- 온라인(`scripts/net.gd`, 자동 로드 Net): toy_racing과 같은 구조. WebRTC 최대 8명, 방장이 가운데. 6자리 방 코드 → ntfy.sh `boardracing-<방코드>` 주제로 `J:`·`O:`·`A:` 교환(SSE, 없으면 3초 폴링). 긴 코드 예비는 `BR1-`. roster `{pid, board, rider, name}`. 위치 묶음은 `race._pack`(높이·공중·묘기 돎 포함).
- CI(`ci.yml`): 소리·아이콘 재생성 확인 → 테스트 → 켜지는지 → 경주가 도는지(`--dev=time`) → 웹 내보내기 → Pages 배포.
- 게임을 크게 바꾸면 조직 첫 화면(mhyoo-games.github.io `games.json`)과 이력서 저장소(minhyuk94.github.io)의 `games` 카드도 ko/ja/en으로 맞춘다. 소스 코드·저장소 링크는 이력서에 넣지 않는다.

## 이 작업 환경에서 돌려 보기

- npm/pip 설치와 github.io 접속이 막혀 있을 수 있다. Godot 실행 파일·웹 템플릿은 dalmaru 저장소의 `godot-bin` 브랜치에서 꺼낸다 (`/opt/godot`에 풀어 둠).
- 테스트: `godot --headless --import` 후 `godot --headless -s tests/run_tests.gd`
- 화면 확인: `xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --audio-driver Dummy -- --dev=<장면> --out=/tmp/x [--track=<id>]` (`scripts/dev.gd`, 장면: title, tracks, shop, help, online, boards(보드 줄 세워 보기), race, team, time, items, tour, pause, results). 경주 장면은 사람 보드도 컴퓨터가 몬다.
- 웹 확인: `godot --headless --export-release "Web" build/web/index.html` 후 로컬 http 서버 + Playwright(`/opt/npm-tools`) + `/usr/bin/google-chrome` (`--use-angle=swiftshader`).
- 온라인 확인: toy_racing과 같다 — 흉내 중계(POST /주제, GET /주제/json, GET /주제/sse)를 띄우고 `?relay=http://127.0.0.1:8770/`. 뒤에 있는 페이지는 `bringToFront()`로 번갈아 앞으로.
