(* Copyright (C)  DooM 2D:Forever Developers
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *)
{$MODE DELPHI}
unit MAPSTRUCT;

{
-----------------------------------
MAPSTRUCT.PAS ������ �� 13.11.07

��������� ���� ������ 1
-----------------------------------
}

{
 ����� ������������ ����� WAD, � ������� ������� � ����� - ���������� ���� �����
 (MAP01, MAP02 � �.�.).

 ����� ������������� ������� ������ (BlockType=BLOCK_NONE)

 ��������� ����� (MAP01, MAP02...):
 --------------------------------------
 SIGNATURE    | Byte[3]         | 'MAP'
 VERSION      | Byte            | $01
 BLOCK1       | TBlock          |
 BLOCK1DATA   | RAW             |
 ...          | ......          |
 BLOCKN       | TBlock          |
 BLOCKNDATA   | RAW             |
 --------------------------------------

 ��������� �����:
 --------------------------------------
 BLOCKTYPE    | Byte     | (BLOCK_TEXTURES, BLOCK_PANELS,...)
 RESERVED     | LongWord | $00000000
 BLOCKSIZE    | LongWord | ������� ���� ���� � ������� (���� ����� record'�)
 --------------------------------------
}

interface

const
  MAP_SIGNATURE = 'MAP';
  BLOCK_NONE      = 0;
  BLOCK_TEXTURES  = 1;
  BLOCK_PANELS    = 2;
  BLOCK_ITEMS     = 3;
  BLOCK_AREAS     = 4;
  BLOCK_MONSTERS  = 5;
  BLOCK_TRIGGERS  = 6;
  BLOCK_HEADER    = 7;

type
  Char16     = packed array[0..15] of Char;
  Char32     = packed array[0..31] of Char;
  Char64     = packed array[0..63] of Char;
  Char100    = packed array[0..99] of Char;
  Char256    = packed array[0..255] of Char;
  Byte128    = packed array[0..127] of Byte;

  TMapHeaderRec_1 = packed record
   MapName:        Char32;
   MapAuthor:      Char32;
   MapDescription: Char256;
   MusicName:      Char64;
   SkyName:        Char64;
   Width:          Word;
   Height:         Word;
  end;

  TTextureRec_1 = packed record
   Resource: Char64;
   Anim:     Byte;
  end;

  TPanelRec_1 = packed record
   X, Y:       Integer;
   Width,
   Height:     Word;
   TextureNum: Word;
   PanelType:  Word;
   Alpha:      Byte;
   Flags:      Byte;
  end;

  TItemRec_1 = packed record
   X, Y:     Integer;
   ItemType: Byte;
   Options:  Byte;
  end;

  TMonsterRec_1 = packed record
   X, Y:        Integer;
   MonsterType: Byte;
   Direction:   Byte;
  end;

  TAreaRec_1 = packed record
   X, Y:      Integer;
   AreaType:  Byte;
   Direction: Byte;
  end;

  TTriggerRec_1 = packed record
   X, Y:         Integer;
   Width,
   Height:       Word;
   Enabled:      Byte;
   TexturePanel: Integer;
   TriggerType:  Byte;
   ActivateType: Byte;
   Keys:         Byte;
   DATA:         Byte128; //WARNING! should be exactly equal to sizeof(TTriggerData)
  end;

  TBlock = packed record
   BlockType: Byte;
   Reserved:  LongWord;
   BlockSize: LongWord;
  end;

  TTexturesRec1Array = array of TTextureRec_1;
  TPanelsRec1Array = array of TPanelRec_1;
  TItemsRec1Array = array of TItemRec_1;
  TMonsterRec1Array = array of TMonsterRec_1;
  TAreasRec1Array = array of TAreaRec_1;
  TTriggersRec1Array = array of TTriggerRec_1;

implementation

end.
