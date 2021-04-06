/* Copyright (C)  Doom 2D: Forever Developers
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 3 of the License ONLY.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>

#include "mapdef.h"

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#define PATHSIZE 1024
#define PANEL_ALLOC_STEP 128

#ifdef _WIN32
# define f_mkdir(name) mkdir(name)
#else
# define f_mkdir(name) mkdir(name, 0777)
#endif

typedef struct {
  int w, h, bpp;
  uint32_t *data;
} img_t;

int g_scale = 1;
int g_bgcell = 512;
int g_fgcell = 512;
int g_nooptimize = 0;
int g_streamstexture = 1; // 0=no, 1=bg, 2=fg
int g_liquidstexture = 3; // 0=no, 1=bg, 2=fg, 3=yes, 4=default

char g_texsec[PATHSIZE] = "TEXTURES";
char g_bgsec[PATHSIZE] = "MEGA_BG";
char g_fgsec[PATHSIZE] = "MEGA_FG";
char g_resdir[PATHSIZE] = "RES";
char g_bgname[PATHSIZE] = "_BACKGROUND";
char g_fgname[PATHSIZE] = "_FOREGROUND";

// indexed with PANEL_ enum
const char *tex_name[] = {
  NULL,
  "WALL",
  NULL,
  NULL,
  "WATER",
  "ACID1",
  "ACID2",
  "STEP",
  "STREAMUP",
  "STREAMDN",
  "DOOR",
  "DOOR",
  NULL,
  "STREAMLT",
  "STREAMRT",
};

const uint32_t map_palette[] = {
  0x00000000,
  0xFFD0D0D0, // WALL
  0x00000000,
  0x00000000,
  0xFFC00000, // WATER
  0xFF00B000, // ACID1
  0xFF0000B0, // ACID2
  0xFF808080, // STEP
  0xFF244874, // STREAMUP
  0xFF607C74, // STREAMDOWN
  0xFF5CDC64, // OPENDOOR
  0xFF40B8D4, // DOOR
  0xFFC000C0, // BLOCKMON
  0xFF0450C8, // STREAMLT
  0xFF388CFC, // STREAMRT
};

map_panel_t *map_pan = NULL;
int map_numpan = 0;
int map_cappan = 0;
map_texture_t *map_tex = NULL;
int map_numtex = 0;

uint16_t map_width = 1600;
uint16_t map_height = 1600;

img_t img_bg = { 0 };
img_t img_fg = { 0 };
img_t img_map = { 0 };

/* option parsing */

#define OPT_NUMSEL 8

typedef enum {
  OPT_BOOL,
  OPT_INT,
  OPT_STR,
  OPT_SEL,
} opt_type_t;

typedef struct {
  opt_type_t type;
  const char *name;
  const char *sel[OPT_NUMSEL];
  union {
    char *val_str;
    int *val_int;
  };
} opt_t;

#define DEF_OPT_BOOL(oname) \
  { .type = OPT_BOOL, .name = #oname, .val_int = &g_##oname }
#define DEF_OPT_INT(oname) \
  { .type = OPT_INT, .name = #oname, .val_int = &g_##oname }
#define DEF_OPT_STR(oname) \
  { .type = OPT_STR, .name = #oname, .val_str = g_##oname }
#define DEF_OPT_SEL(oname, ...) \
  { .type = OPT_SEL, .name = #oname, .sel = { __VA_ARGS__ }, .val_int = &g_##oname }

const opt_t opt_defs[] = {
  DEF_OPT_INT(scale),
  DEF_OPT_INT(bgcell),
  DEF_OPT_INT(fgcell),
  DEF_OPT_BOOL(nooptimize),
  DEF_OPT_STR(texsec),
  DEF_OPT_STR(bgsec),
  DEF_OPT_STR(fgsec),
  DEF_OPT_STR(resdir),
  DEF_OPT_SEL(streamstexture, "no", "bg", "fg"),
  DEF_OPT_SEL(liquidstexture, "no", "bg", "fg", "yes", "xtra"),
};

const size_t opt_numdefs = sizeof(opt_defs) / sizeof(opt_t);

const char *opt_parse(const char *str) {
  if (!str || str[0] != '-' || str[1] != '-' || !str[2])
    return "invalid option string";

  str += 2;

  char *eq = strrchr(str, '=');
  if (eq) *eq = 0;
  const char *opts = str;
  const char *vals = eq ? eq + 1 : NULL;

  for (int i = 0; i < opt_numdefs; ++i) {
    if (strcmp(opts, opt_defs[i].name))
      continue;

    switch (opt_defs[i].type) {
      case OPT_BOOL:
        if (eq) return "don't need an explicit value";
        *opt_defs[i].val_int = 1;
        return NULL;
      case OPT_INT:
        if (!eq) return "need numeric value";
        *opt_defs[i].val_int = atoi(vals);
        return NULL;
      case OPT_STR:
        if (!eq) return "need string value";
        strncpy(opt_defs[i].val_str, vals, PATHSIZE);
        opt_defs[i].val_str[PATHSIZE-1] = 0;
        return NULL;
      case OPT_SEL:
        if (!eq) return "need string value";
        for (int j = 0; j < OPT_NUMSEL && opt_defs[i].sel[j]; ++j) {
          if (!strcmp(opt_defs[i].sel[j], vals)) {
            *opt_defs[i].val_int = j;
            return NULL;
          }
        }
        return "invalid variant value";
      default:
        break;
    }
  }

  return "unknown option";
}

/* -------------- */

/* map writing */

int map_save(const char *fname) {
  FILE *fout = fopen(fname, "wb");
  if (!fout) return -1;

  map_header_t hdr = { { 0 } };
  strcpy(hdr.name, "png2map map");
  strcpy(hdr.author, "png2map");
  strcpy(hdr.desc, "generated by png2map");
  hdr.music[0] = 0;
  hdr.sky[0] = 0;
  hdr.width = map_width;
  hdr.height = map_height;

  map_block_t blk = { MBLK_HEADER, 0, sizeof(hdr) };

  fwrite(MAP_MAGIC, 4, 1, fout);
  fwrite(&blk, sizeof(blk), 1, fout);
  fwrite(&hdr, sizeof(hdr), 1, fout);

  if (map_numtex > 0) {
    blk.type = MBLK_TEXTURES;
    blk.size = sizeof(map_texture_t) * map_numtex;
    fwrite(&blk, sizeof(blk), 1, fout);
    for (int i = 0; i < map_numtex; ++i)
      fwrite(map_tex + i, sizeof(map_texture_t), 1, fout);
  }

  if (map_numpan > 0) {
    blk.type = MBLK_PANELS;
    blk.size = sizeof(map_panel_t) * map_numpan;
    fwrite(&blk, sizeof(blk), 1, fout);
    for (int i = 0; i < map_numpan; ++i)
      fwrite(map_pan + i, sizeof(map_panel_t), 1, fout);
  }

  blk.type = MBLK_NONE;
  blk.size = 0;
  fwrite(&blk, sizeof(blk), 1, fout);

  return 0;
}

int map_cachetex(const char *name) {
  static char path[PATHSIZE];

  if (!name || !name[0])
    return -1;

  if (!strncmp(name, "_water_", 7))
    snprintf(path, PATHSIZE, name);
  else if (strchr(name, '\\'))
    snprintf(path, PATHSIZE, ":\\%s.PNG", name);
  else
    snprintf(path, PATHSIZE, ":\\%s\\%s.PNG", g_texsec, name);

  for (int i = 0; i < map_numtex; ++i)
    if (!strncmp(path, map_tex[i].resname, 64))
      return i;

  int i = map_numtex++;
  map_tex = realloc(map_tex, map_numtex * sizeof(map_texture_t));
  if (!map_tex) return -1;

  map_tex[i].anim = 0;
  strncpy(map_tex[i].resname, path, 64);
  map_tex[i].resname[63] = 0;

  return i;
}

int map_addpanel(int type, const char *tex, int x, int y, int w, int h) {
  if (!type) return -2;

  if (map_numpan >= map_cappan) {
    map_cappan += PANEL_ALLOC_STEP;
    map_pan = realloc(map_pan, map_cappan * sizeof(map_panel_t));
    if (!map_pan) return -1;
  }

  int texid = map_cachetex(tex);
  int i = map_numpan++;
  memset(map_pan + i, 0, sizeof(map_panel_t));
  map_pan[i].type = 1 << (type - 1);
  if (texid >= 0)
    map_pan[i].texid = texid;
  else
    map_pan[i].flags = PFLAG_HIDE;
  if (type >= PANEL_WATER && type <= PANEL_ACID2)
    map_pan[i].flags |= PFLAG_WATERTEXTURES;
  map_pan[i].x = x;
  map_pan[i].y = y;
  map_pan[i].w = w;
  map_pan[i].h = h;

  return i;
}

/* ----------- */

/* image shit */

int img_load(const char *fname, img_t *out) {
  out->data = (uint32_t *)stbi_load(fname, &out->w, &out->h, &out->bpp, 4);
  return !out->data;
}

void img_free(img_t *img) {
  free(img->data);
  img->data = NULL;
}

img_t *img_segment(img_t *src, int cell, int *out_cx, int *out_cy) {
  if (!src || !src->data || cell <= 0) return NULL;

  int cx = (src->w + cell - 1) / cell;
  int cy = (src->h + cell - 1) / cell;
  int cn = cx * cy;

  img_t *cells = calloc(cn, sizeof(img_t));
  if (!cells) return NULL;
  for (int i = 0; i < cn; ++i) {
    cells[i].w = cells[i].h = cell;
    cells[i].data = calloc(cell * cell, 4);
    if (!cells[i].data) {
      free(cells);
      return NULL;
    }
  }

  // this is awfully retarded, but who cares
  uint32_t *inp = src->data;
  for (int y = 0; y < src->h; ++y) {
    int cell_y = y / cell;
    for (int x = 0; x < src->w; ++x, ++inp) {
      int pos_y = y % cell;
      int pos_x = x % cell;
      int pos = pos_y * cell + pos_x;
      cells[cell_y * cx + x / cell].data[pos] = *inp;
    }
  }

  *out_cx = cx;
  *out_cy = cy;
  return cells;
}

int img_save(const char *fname, img_t *src) {
  static char path[PATHSIZE];
  if (!src || !src->data) return -1;
  if (!strstr(fname, ".png"))
    snprintf(path, sizeof(path), "%s.png", fname);
  else
    snprintf(path, sizeof(path), fname);
  return !stbi_write_png(path, src->w, src->h, 4, src->data, 4 * src->w);
}

/* ---------- */

void die(const char *fmt, ...) {
  fprintf(stderr, "FATAL ERROR: ");
  va_list args;
  va_start(args, fmt);
  vfprintf(stderr, fmt, args);
  va_end(args);
  fprintf(stderr, "\n");

  if (img_bg.data) img_free(&img_bg);
  if (img_fg.data) img_free(&img_fg);
  if (img_map.data) img_free(&img_map);
  if (map_pan) free(map_pan);
  if (map_tex) free(map_tex);

  exit(1);
}

void tex_check(const char *resdir, int liquidsmode) {
  static const char *liquids[] = { "_water_0", "_water_1", "_water_2" };
  char path[PATHSIZE] = { 0 };

  if (!liquidsmode) {
    tex_name[PANEL_WATER] = tex_name[PANEL_ACID1] = tex_name[PANEL_ACID2] = NULL;
  } else if (liquidsmode == 4) {
    tex_name[PANEL_WATER] = liquids[0];
    tex_name[PANEL_ACID1] = liquids[1];
    tex_name[PANEL_ACID2] = liquids[2];
  }

  for (int i = 0; i < PANEL_NUMTYPES; ++i) {
    if (!tex_name[i]) continue;
    snprintf(path, PATHSIZE, "%s/%s.png", resdir, tex_name[i]);
    FILE *f = fopen(path, "rb");
    if (f) {
      fclose(f);
    } else {
      printf("texture `%s` missing from `%s`, using default\n", tex_name[i], resdir);
      if (i >= PANEL_WATER && i <= PANEL_ACID2 && liquidsmode)
        tex_name[i] = liquids[i - PANEL_WATER];
      else
        tex_name[i] = NULL;
    }
  }
}

void scronch_layer(int layer, img_t *img, int cellsize, const char *secname) {
  int numx = 1;
  int numy = 1;
  img_t *cells = cellsize ? img_segment(img, cellsize, &numx, &numy) : img;

  if (!numx || !numy || !cells)
    die("scronching failure");

  f_mkdir(secname);

  int pw, ph;
  if (cellsize) {
    pw = ph = cellsize;
  } else {
    pw = img->w;
    ph = img->h;
  }

  char path[PATHSIZE] = { 0 };
  for (int yc = 0; yc < numy; ++yc) {
    int y = yc * cellsize;
    for (int xc = 0; xc < numx; ++xc) {
      int x = xc * cellsize;
      int idx = yc * numx + xc;
      snprintf(path, PATHSIZE, "%s\\BG%03X%03X", secname, xc, yc);
      if (img_save(path, cells + idx))
        die("could not save layer cell `%s`", path);
      if (cells != img)
        img_free(cells + idx);
      if (map_addpanel(layer, path, x, y, pw, ph) < 0)
        die("could not add layer panel");
    }
  }

  if (cells != img)
    free(cells);
}

static inline uint32_t type_for_color(const uint32_t c) {
  if (!c) return 0; // empty
  for (int i = 0; i < PANEL_NUMTYPES; ++i)
    if (map_palette[i] == c)
      return i;
  return 0;
}

static inline int spawn_panel(uint32_t type, int x, int y, int w, int h) {
  const char *tex = tex_name[type];

  switch (type) {
    case PANEL_WATER:
    case PANEL_ACID1:
    case PANEL_ACID2:
      if (g_liquidstexture == 1 || g_liquidstexture == 2) {
        map_addpanel(PANEL_BACK + g_liquidstexture - 1, tex, x, y, w, h);
        tex = NULL;
      }
      break;
    case PANEL_LIFTUP:
    case PANEL_LIFTDOWN:
    case PANEL_LIFTLEFT:
    case PANEL_LIFTRIGHT:
      if (g_streamstexture == 1 || g_streamstexture == 2) {
        map_addpanel(PANEL_BACK + g_streamstexture - 1, tex, x, y, w, h);
        tex = NULL;
      }
      break;
    default:
      break;
  }

  map_addpanel(type, tex, x, y, w, h);
}

static inline void fill_panel_opt(const img_t *img, uint8_t *done, int x1, int y1, int scale) {
  #define PIXEQ(xx, yy) (img->data[(yy) * w + (xx)] == c1)
  #define DONE(xx, yy) (done[(yy) * w + (xx)])
  const uint32_t c1 = img->data[y1 * img->w + x1];
  const uint32_t type = type_for_color(c1);
  if (!type) {
    done[y1 * img->w + x1] = 1;
    return; // unknown panel or emptiness
  }

  const int w = img->w;
  const int h = img->h;

  // this ain't optimal, but it'll do

  // find horizontal bounds
  int ml = x1, mr = x1;
  for (; ml > 0 && !DONE(ml-1, y1) && PIXEQ(ml-1, y1); --ml);
  for (; mr < w-1 && !DONE(mr+1, y1) && PIXEQ(mr+1, y1); ++mr);

  // find min vertical bounds
  int mu = 0, md = h - 1;
  for (int x = ml; x <= mr; ++x) {
    int tu, td;
    for (tu = y1; tu > 0 && !DONE(x, tu-1) && PIXEQ(x, tu-1); --tu);
    for (td = y1; td < h-1 && !DONE(x, td+1) && PIXEQ(x, td+1); ++td);
    if (tu > mu) mu = tu;
    if (td < md) md = td;
  }

  // don't overlap this later
  for (int y = mu; y <= md; ++y)
    for (int x = ml; x <= mr; ++x)
      DONE(x, y) = 1;

  int pw = (mr - ml + 1);
  int ph = (md - mu + 1);
  if (spawn_panel(type, ml * scale, mu * scale, scale * pw, scale * ph) < 0)
    die("could not add panel at (%d, %d) x (%d, %d)", ml, mu, pw, ph);
  #undef PIX
  #undef DONE
}

static inline void fill_panel_single(const img_t *img, uint8_t *done, int x1, int y1, int scale) {
  const uint32_t c1 = img->data[y1 * img->w + x1];
  const uint32_t type = type_for_color(c1);
  done[y1 * img->w + x1] = 1;
  if (!type) return; // unknown panel or emptiness
  spawn_panel(type, x1 * scale, y1 * scale, scale, scale);
}

static inline void fill_panel(const img_t *img, uint8_t *done, int x1, int y1, int scale) {
  if (g_nooptimize)
    fill_panel_single(img, done, x1, y1, scale);
  else
    fill_panel_opt(img, done, x1, y1, scale);
}

void convert_map(img_t *img, int scale) {
  if (!img || !img->data) return;

  uint8_t *done = calloc(1, img->w * img->h);

  for (int x = 0; x < img->w; ++x) {
    for (int y = 0; y < img->h; ++y) {
      if (done[y * img->w + x]) continue;
      fill_panel(img, done, x, y, scale);
    }
  }

  map_width = img->w * scale;
  map_height = img->h * scale;
}

int main(int argc, const char **argv) {
  if (argc < 3) {
    printf("usage: %s <input> <output> [options...]\n", argv[0]);
    return -1;
  }

  for (int i = 3; i < argc; ++i) {
    const char *err = opt_parse(argv[i]);
    if (err) printf("error parsing option `%s`: %s\n", argv[i], err);
  }

  char path[PATHSIZE];

  tex_check(g_resdir, !g_liquidstexture);

  if (img_load(argv[1], &img_map))
    die("could not load map image `%s`", argv[1]);

  snprintf(path, sizeof(path), "%s/%s.png", g_resdir, g_bgname);
  if (!img_load(path, &img_bg)) {
    printf("scronching background: %s\n", path);
    scronch_layer(PANEL_BACK, &img_bg, g_bgcell, g_bgsec);
    img_free(&img_bg);
  }

  snprintf(path, sizeof(path), "%s/%s.png", g_resdir, g_fgname);
  if (!img_load(path, &img_fg)) {
    printf("scronching foreground: %s\n", path);
    scronch_layer(PANEL_FORE, &img_fg, g_fgcell, g_fgsec);
    img_free(&img_fg);
  }

  printf("converting map from image `%s` (%dx%d)\n", argv[1], img_map.w, img_map.h);
  convert_map(&img_map, g_scale);
  map_save(argv[2]);
  img_free(&img_map);

  return 0;
}
