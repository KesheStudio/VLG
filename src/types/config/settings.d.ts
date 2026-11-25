interface AudioConfigItem {
  isPlay:boolean;
  isFadePlay?:boolean;
  fadeTime?:number;
  volume:number
}

interface AudioConfig {
  music:AudioConfigItem;
  dialogue:AudioConfigItem;
  sfx:AudioConfigItem
}

export interface Settings {
  audio:AudioConfig
}