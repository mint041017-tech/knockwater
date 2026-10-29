/* 关卡数据：坐标单位为格（水面 12 × 20） */
window.LEVELS = [
  {
    name: "初纹",
    hint: "按住水面拖动，水铃就会走过去。每走一步，都会荡开一圈铃波——波会替你推开花瓣。",
    charges: 12,
    bell: [3, 13],
    bay: { x: 8.5, y: 8.0, r: 1.35 },
    petals: [{ x: 6.4, y: 10.4, w: 1 }],
    rocks: [],
    reeds: [],
    echoes: [],
    currents: []
  },
  {
    name: "石语",
    hint: "墨石会把铃波挡回去。绕开它——最短的路，反而会把花瓣推歪。",
    charges: 16,
    bell: [2, 10],
    bay: { x: 9.0, y: 10.5, r: 1.3 },
    petals: [{ x: 6.5, y: 10.5, w: 1 }],
    rocks: [{ x: 4.5, y: 10.5, r: 0.85 }],
    reeds: [],
    echoes: [],
    currents: []
  },
  {
    name: "双生",
    hint: "两片花瓣，一个湾心。先送近的，再绕到另一片的背后。",
    charges: 24,
    bell: [6, 15],
    bay: { x: 6.0, y: 10.2, r: 1.65 },
    petals: [
      { x: 4.4, y: 7.4, w: 1 },
      { x: 7.6, y: 12.6, w: 1 }
    ],
    rocks: [],
    reeds: [],
    echoes: [],
    currents: []
  },
  {
    name: "绕壁",
    hint: "石墙横在池中。要到花瓣的另一侧，你得先绕很远——而每一步都会惊动它。",
    charges: 20,
    bell: [2, 10],
    bay: { x: 3.5, y: 13.0, r: 1.35 },
    petals: [{ x: 8.0, y: 13.0, w: 1 }],
    rocks: [
      { x: 6, y: 4, r: 1.0 },
      { x: 6, y: 6, r: 1.0 },
      { x: 6, y: 8, r: 1.0 },
      { x: 6, y: 10, r: 1.0 }
    ],
    reeds: [],
    echoes: [],
    currents: []
  },
  {
    name: "暗流",
    hint: "暗流把花瓣往东推。想让它往北，就先往西北多给一点。",
    charges: 20,
    bell: [4, 15],
    bay: { x: 8.2, y: 8.0, r: 1.4 },
    petals: [{ x: 6.0, y: 12.4, w: 1 }],
    rocks: [],
    reeds: [],
    echoes: [],
    currents: [
      { x: 4.2, y: 10.0, r: 2.1, dx: 0.5, dy: 0 },
      { x: 6.4, y: 10.0, r: 2.1, dx: 0.5, dy: 0 },
      { x: 8.6, y: 10.0, r: 2.1, dx: 0.5, dy: 0 }
    ]
  },
  {
    name: "浅岸",
    hint: "北岸很近。重叩会把花瓣推上浅滩——这一次，轻一点。",
    charges: 18,
    bell: [6, 12],
    bay: { x: 6.4, y: 4.2, r: 1.15 },
    petals: [{ x: 6.2, y: 8.6, w: 1 }],
    rocks: [],
    reeds: [{ x: 6.4, y: 6.5, r: 0.85 }],
    echoes: [],
    currents: []
  },
  {
    name: "合鸣",
    hint: "最后一段水路：两片花瓣，一道暗流。让它们自己漂进湾心。",
    charges: 30,
    bell: [6, 16],
    bay: { x: 6.0, y: 8.0, r: 1.7 },
    petals: [
      { x: 3.6, y: 12.2, w: 1 },
      { x: 8.4, y: 12.2, w: 1 }
    ],
    rocks: [{ x: 6.0, y: 12.2, r: 0.9 }],
    reeds: [],
    echoes: [],
    currents: [
      { x: 3.8, y: 10.0, r: 1.8, dx: 0.5, dy: 0 },
      { x: 6.6, y: 10.0, r: 1.8, dx: 0.5, dy: 0 },
      { x: 9.4, y: 10.0, r: 1.8, dx: 0.5, dy: 0 }
    ]
  }
];
