/* SPDX-License-Identifier: GPL-2.0 */
/*
 * NVM Express device driver tracepoints
 * Copyright (c) 2018 Johannes Thumshirn, SUSE Linux GmbH
 */

#undef TRACE_SYSTEM
#define TRACE_SYSTEM nvme

#if !defined(_TRACE_NVME_H) || defined(TRACE_HEADER_MULTI_READ)
#define _TRACE_NVME_H

#include <linux/nvme.h>
#include <linux/tracepoint.h>
#include <linux/trace_seq.h>

#include "nvme.h"

const char *nvme_trace_parse_admin_cmd(struct trace_seq *p, u8 opcode,
		u8 *cdw10);
const char *nvme_trace_parse_nvm_cmd(struct trace_seq *p, u8 opcode,
		u8 *cdw10);
const char *nvme_trace_parse_fabrics_cmd(struct trace_seq *p, u8 fctype,
		u8 *spc);

#define parse_nvme_cmd(qid, opcode, fctype, cdw10)			\
	((opcode) == nvme_fabrics_command ?				\
	 nvme_trace_parse_fabrics_cmd(p, fctype, cdw10) :		\
	((qid) ?							\
	 nvme_trace_parse_nvm_cmd(p, opcode, cdw10) :			\
	 nvme_trace_parse_admin_cmd(p, opcode, cdw10)))

const char *nvme_trace_disk_name(struct trace_seq *p, char *name);
#define __print_disk_name(name)				\
	nvme_trace_disk_name(p, name)

#ifndef TRACE_HEADER_MULTI_READ
static inline void __assign_disk_name(char *name, struct gendisk *disk)
{
	if (disk)
		memcpy(name, disk->disk_name, DISK_NAME_LEN);
	else
		memset(name, 0, DISK_NAME_LEN);
}
#endif


#endif /* _TRACE_NVME_H */

#undef TRACE_INCLUDE_PATH
#define TRACE_INCLUDE_PATH .
#undef TRACE_INCLUDE_FILE
#define TRACE_INCLUDE_FILE trace

// /* This part must be outside protection */
// #include <trace/define_trace.h>
