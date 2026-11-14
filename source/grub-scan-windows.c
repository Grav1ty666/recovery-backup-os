/* GRUB EFI Windows boot entry scanner. GPL-3.0-or-later. */
#include <grub/types.h>
#include <grub/mm.h>
#include <grub/misc.h>
#include <grub/charset.h>
#include <grub/env.h>
#include <grub/command.h>
#include <grub/efi/efi.h>
#include <grub/device.h>
#include <grub/disk.h>
#include <grub/partition.h>
#include <grub/gpt_partition.h>
#include <grub/file.h>

GRUB_MOD_LICENSE ("GPLv3+");
static grub_command_t scan_command;
static grub_guid_t global_guid = GRUB_EFI_GLOBAL_VARIABLE_GUID;

struct disk_match { grub_uint8_t guid[16]; char *name; const char *path; unsigned int count; };
static int match_disk (const char *name, void *context)
{
  struct disk_match *match = context;
  grub_device_t dev = grub_device_open (name);
  grub_disk_t disk;
  struct grub_gpt_partentry entry;
  char *filename;
  grub_file_t file;
  if (!dev) { grub_errno = GRUB_ERR_NONE; return 0; }
  if (!dev->disk || !dev->disk->partition ||
      grub_strcmp (dev->disk->partition->partmap->name, "gpt") != 0)
    { grub_device_close (dev); return 0; }
  disk = grub_disk_open (dev->disk->name);
  if (!disk) { grub_errno = GRUB_ERR_NONE; grub_device_close (dev); return 0; }
  if (grub_disk_read (disk, dev->disk->partition->offset,
                      dev->disk->partition->index, sizeof (entry), &entry) ||
      grub_memcmp (&entry.guid, match->guid, sizeof (match->guid)))
    { grub_errno = GRUB_ERR_NONE; grub_disk_close (disk); grub_device_close (dev); return 0; }
  grub_disk_close (disk); grub_device_close (dev);
  filename = grub_xasprintf ("(%s)%s", name, match->path);
  if (!filename) return 1;
  file = grub_file_open (filename, GRUB_FILE_TYPE_FS_SEARCH);
  grub_free (filename);
  if (!file) { grub_errno = GRUB_ERR_NONE; return 0; }
  grub_file_close (file);
  match->count++;
  if (match->count == 1) match->name = grub_strdup (name);
  return 0;
}

/* Parse the UEFI EFI_LOAD_OPTION header and its bounded device-path list. */
static int parse_option (const grub_uint8_t *data, grub_size_t size,
                         char **description, grub_uint8_t *guid, char *path, grub_size_t path_size)
{
  grub_size_t pos = 6, text_len = 0, path_start, path_end, out = 0;
  grub_uint16_t label[257];
  int got_guid = 0, found_end = 0;
  grub_uint16_t file_len;
  if (size < 8 || !(data[0] & 1)) return 0; /* active entries only */
  file_len = data[4] | ((grub_uint16_t)data[5] << 8);
  while (pos + 1 < size)
    {
      grub_uint16_t c = data[pos] | ((grub_uint16_t)data[pos + 1] << 8);
      pos += 2;
      if (!c) break;
      if (c < 0x20 || c == 0x7f || text_len >= 256) return 0;
      label[text_len++] = c;
    }
  if (!text_len || pos > size || data[pos-1] || data[pos-2]) return 0;
  path_start = pos;
  if (file_len < 4 || file_len > size - path_start) return 0;
  path_end = path_start + file_len;
  while (pos + 4 <= path_end)
    {
      unsigned type = data[pos], subtype = data[pos+1];
      grub_size_t len = data[pos+2] | ((grub_uint16_t)data[pos+3] << 8);
      grub_size_t i;
      if (len < 4 || len > path_end - pos) return 0;
      if (type == 4 && subtype == 1 && len == 42 && data[pos+41] == 2)
        { if (got_guid) return 0; grub_memcpy (guid, data+pos+24, 16); got_guid = 1; }
      if (type == 4 && subtype == 4)
        {
          if ((len & 1) || len < 6) return 0;
          if (out && path[out-1] != '/' && data[pos+4] != '\\' && data[pos+4] != '/')
            { if (out >= path_size-1) return 0; path[out++] = '/'; }
          for (i = pos+4; i+1 < pos+len; i += 2)
            {
              unsigned c = data[i] | ((unsigned)data[i+1] << 8);
              if (!c) break;
              if (c < 0x20 || c > 126 || out >= path_size-1) return 0;
              path[out++] = (c == '\\') ? '/' : (char)c;
            }
          if (i+1 >= pos+len || data[i] || data[i+1]) return 0;
        }
      pos += len;
      if (type == 0x7f && subtype == 0xff && len == 4)
        { found_end = 1; break; }
    }
  path[out] = 0;
  if (!got_guid || !found_end || pos != path_end || path[0] != '/' || out < 5 ||
      grub_strcasecmp (path + out - 4, ".efi") != 0 ||
      grub_strcasecmp (path, "/EFI/clonezilla/grubx64.efi") == 0) return 0;
  *description = grub_malloc (text_len * 4 + 1);
  if (!*description) return 0;
  *grub_utf16_to_utf8 ((grub_uint8_t *)*description, label, text_len) = 0;
  return 1;
}

static grub_size_t cursor;
static grub_err_t scan_windows (grub_command_t cmd __attribute__ ((unused)), int argc, char **argv)
{
  grub_size_t order_size = 0, i;
  grub_uint8_t *order = NULL;
  grub_efi_status_t status;
  if (argc != 1) return grub_error (GRUB_ERR_BAD_ARGUMENT, "mode required");
  if (!grub_strcmp (argv[0], "reset")) { cursor = 0; return GRUB_ERR_NONE; }
  if (grub_strcmp (argv[0], "windows") && grub_strcmp (argv[0], "other"))
    return grub_error (GRUB_ERR_BAD_ARGUMENT, "invalid scan mode");
  grub_env_unset ("detected_boot_name");
  grub_env_unset ("detected_boot_device");
  grub_env_unset ("detected_boot_path");
  status = grub_efi_get_variable ("BootOrder", &global_guid, &order_size, (void **)&order);
  if (status != GRUB_EFI_SUCCESS || !order || (order_size & 1))
    { grub_free (order); return grub_error (GRUB_ERR_FILE_NOT_FOUND, "UEFI BootOrder unavailable"); }
  for (i = cursor; i + 1 < order_size; i += 2)
    {
      char key[9], path[512]; char *label = NULL;
      grub_uint8_t *data = NULL, guid[16]; grub_size_t size = 0;
      struct disk_match match;
      grub_memset (&match, 0, sizeof(match));
      grub_snprintf (key, sizeof(key), "Boot%04X", order[i] | ((unsigned)order[i+1] << 8));
      status = grub_efi_get_variable (key, &global_guid, &size, (void **)&data);
      if (status != GRUB_EFI_SUCCESS || !data) continue;
      if (!parse_option (data, size, &label, guid, path, sizeof(path))) { grub_free (data); continue; }
      grub_free (data); grub_memcpy (match.guid, guid, sizeof(guid));
      if ((!grub_strcmp (argv[0], "windows")) != (!grub_strcasecmp (path, "/EFI/Microsoft/Boot/bootmgfw.efi")))
        { grub_free (label); continue; }
      match.path = path;
      grub_device_iterate (match_disk, &match);
      if (match.count == 1 && match.name && grub_errno == GRUB_ERR_NONE)
        {
          cursor = i + 2;
          grub_env_set ("detected_boot_name", label);
          grub_env_set ("detected_boot_device", match.name);
          grub_env_set ("detected_boot_path", path);
          grub_free (label); grub_free (match.name); grub_free (order);
          return grub_errno;
        }
      grub_free (label); grub_free (match.name); grub_errno = GRUB_ERR_NONE;
    }
  grub_free (order);
  return grub_error (GRUB_ERR_TEST_FAILURE, "No more matching UEFI boot entries");
}
GRUB_MOD_INIT(lsefi) { scan_command = grub_register_command ("scan_uefi_boot", scan_windows, 0, "Scan UEFI boot entries"); }
GRUB_MOD_FINI(lsefi) { grub_unregister_command (scan_command); }
