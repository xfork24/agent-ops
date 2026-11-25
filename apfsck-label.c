/*
 * apfs-label: 显示 / 修改 APFS 卷的卷名（volume name）
 *
 * 基于 apfsprogs 的 apfsck（Ernesto A. Fernández），
 * 复用其容器/omap 解析来定位卷超级块，避免重复实现 omap btree 解析。
 *
 * 新增选项：
 *   -I          只读：打印容器里各卷的编号/块号/名称/UUID
 *   -L <label>  把卷名改成 <label>（写盘前会重算 Fletcher64 校验和）
 *   -i <index>  指定要操作的卷编号（默认第一个）
 *   -B <file>   修改前把原始卷超级块备份到 <file>
 */

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <apfs/checksum.h>
#include <apfs/raw.h>
#include <apfs/types.h>
#include "apfsck.h"
#include "super.h"

static void print_uuid(const u8 *uuid)
{
	printf("%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-"
	       "%02x%02x%02x%02x%02x%02x",
	       uuid[0], uuid[1], uuid[2], uuid[3], uuid[4], uuid[5], uuid[6],
	       uuid[7], uuid[8], uuid[9], uuid[10], uuid[11], uuid[12], uuid[13],
	       uuid[14], uuid[15]);
}

int print_volume_info(const char *filename)
{
	int vol;
	int found = 0;

	printf("设备/镜像: %s\n", filename);
	for (vol = 0; vol < APFS_NX_MAX_FILE_SYSTEMS; ++vol) {
		struct volume_superblock *v = sb->s_volumes[vol];
		struct apfs_superblock *raw;

		if (!v)
			continue;
		raw = v->v_raw;
		found = 1;
		printf("卷[%d] 块号=%llu xid=%llu 名称=\"%s\" UUID=",
		       vol, (unsigned long long)v->v_obj.block_nr,
		       (unsigned long long)v->v_obj.xid,
		       (char *)raw->apfs_volname);
		print_uuid((const u8 *)raw->apfs_vol_uuid);
		printf("\n");
	}
	if (!found)
		printf("没有找到卷超级块\n");
	return found ? 0 : 1;
}

int set_volume_label(const char *filename, const char *label, int vol_index,
		     const char *backup_path)
{
	struct volume_superblock *v;
	struct apfs_superblock *writable;
	struct apfs_obj_phys *obj;
	char old_name[APFS_VOLNAME_LEN];
	size_t len = strlen(label);
	size_t bsize;
	void *map;
	int wfd;

	if (!len || len + 1 > APFS_VOLNAME_LEN) {
		fprintf(stderr, "卷名长度非法（最多 %d 字节）\n",
			APFS_VOLNAME_LEN - 1);
		return 1;
	}

	if (vol_index < 0) {
		for (vol_index = 0; vol_index < APFS_NX_MAX_FILE_SYSTEMS;
		     ++vol_index)
			if (sb->s_volumes[vol_index])
				break;
	}
	if (vol_index >= APFS_NX_MAX_FILE_SYSTEMS ||
	    !sb->s_volumes[vol_index]) {
		fprintf(stderr, "没有编号为 %d 的卷\n", vol_index);
		return 1;
	}

	v = sb->s_volumes[vol_index];
	bsize = sb->s_blocksize;

	wfd = open(filename, O_RDWR);
	if (wfd == -1)
		system_error();
	map = mmap(NULL, bsize, PROT_READ | PROT_WRITE, MAP_SHARED, wfd,
		   (off_t)v->v_obj.block_nr * bsize);
	if (map == MAP_FAILED)
		system_error();

	if (backup_path) {
		FILE *f = fopen(backup_path, "wb");

		if (!f)
			system_error();
		if (fwrite(map, 1, bsize, f) != bsize)
			system_error();
		fclose(f);
		printf("原始卷超级块(块 %llu)已备份到 %s\n",
		       (unsigned long long)v->v_obj.block_nr, backup_path);
	}

	writable = (struct apfs_superblock *)map;

	/* 先留一份旧名，下面覆盖后就取不到了 */
	snprintf(old_name, sizeof(old_name), "%s", (char *)writable->apfs_volname);

	/* 写入新卷名，剩余部分清零 */
	memcpy(writable->apfs_volname, label, len + 1);
	memset(writable->apfs_volname + len + 1, 0,
	       APFS_VOLNAME_LEN - len - 1);

	/* 重算对象头的 Fletcher64 校验和（覆盖对象头之后的整块） */
	obj = (struct apfs_obj_phys *)map;
	obj->o_cksum = cpu_to_le64(fletcher64((char *)map + APFS_MAX_CKSUM_SIZE,
					       bsize - APFS_MAX_CKSUM_SIZE));

	if (msync(map, bsize, MS_SYNC) < 0)
		system_error();
	if (fsync(wfd) < 0)
		system_error();
	munmap(map, bsize);
	close(wfd);

	printf("卷[%d] 名称: \"%s\" -> \"%s\"（校验和已重算）\n", vol_index,
	       old_name, label);
	return 0;
}
