#
# This file is part of the Valkyrja GitHub package.
#
# Copyright (c) 2016-present Melech Mizrachi
#
# Released under the MIT License. See LICENSE.md for details.
#
# ---------------------------------------------------------------------------
# Required job merge for a consumer `ci.yml`.
#
# `required-workflows/ci.yml` names the jobs that every repository runs. A
# repository may add jobs of its own, so this script adds only the jobs that
# the repository does not have, and it leaves the rest of the file alone.
#
# Each missing job goes after the job that precedes it in the template order,
# so the merged file keeps the template's order wherever the two agree.
#
# Reads the existing file and the template as arguments, and writes the merged
# file to standard output. Exits 3 when the repository already has every job,
# which tells the caller that nothing needs a commit.
#
# Warning: 3 rather than 1, because an uncaught exception also exits 1. The
# caller cannot tell a crash from an answer when the two share a code, and it
# read every crash as "every job is present".
#
# Usage:
#
#     python3 merge_ci_jobs.py <existing ci.yml> <template ci.yml>
# ---------------------------------------------------------------------------

import re, sys

existing = open(sys.argv[1]).read()
template = open(sys.argv[2]).read()

def get_job_ids_ordered(content):
    return re.findall(r'^\s{2}([a-zA-Z][a-zA-Z0-9_-]*):\s*$', content, re.MULTILINE)

def get_job_block(content, job_id):
    pattern = rf'(  {re.escape(job_id)}:.*?)(?=\n\n  [a-zA-Z]|\Z)'
    m = re.search(pattern, content, re.DOTALL)
    return m.group(1) if m else None

existing_jobs_ordered = get_job_ids_ordered(existing)
existing_jobs = set(existing_jobs_ordered)
template_job_order = get_job_ids_ordered(template)
missing = [j for j in template_job_order if j not in existing_jobs]

if not missing:
    sys.exit(3)

if not existing_jobs:
    sys.stdout.write(template if template.endswith('\n') else template + '\n')
    sys.exit(0)

result = existing.rstrip('\n')

for job_id in missing:
    block = get_job_block(template, job_id)
    if not block:
        continue

    job_pos = template_job_order.index(job_id)

    # Find the last existing job that precedes this one in the template order
    predecessor = None
    for i in range(job_pos - 1, -1, -1):
        if template_job_order[i] in existing_jobs:
            predecessor = template_job_order[i]
            break

    if predecessor:
        pred_pattern = rf'(  {re.escape(predecessor)}:.*?)(\n\n  [a-zA-Z]|\n*\Z)'
        insertion = r'\1' + '\n\n' + block.rstrip('\n') + r'\2'
        result = re.sub(pred_pattern, insertion, result, count=1, flags=re.DOTALL)
    else:
        jobs_start = re.search(r'^jobs:\s*\n', result, re.MULTILINE)
        if jobs_start:
            pos = jobs_start.end()
            result = result[:pos] + block.rstrip('\n') + '\n\n' + result[pos:]

    existing_jobs.add(job_id)

result += '\n'
sys.stdout.write(result)
