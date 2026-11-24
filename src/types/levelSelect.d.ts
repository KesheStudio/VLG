export interface levelSelectNode {
  levelID:string;
  levelFile:string;
  levelName:string;
  title:string;
  sideQuest?:levelSelectNode[]
}