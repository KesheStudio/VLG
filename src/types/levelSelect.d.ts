export interface LevelSelectNode {
  levelID:string;
  levelFile:string;
  levelName:string;
  title:string;
  sideQuest?:levelSelectNode[]
}