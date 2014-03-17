#!/usr/bin/env python
# Incrementally admit workers to the second session of the study.

import argparse, json, time
import boto.mturk.connection

EMAIL_SUBJECT = 'Invitation to participate in a new HIT'
EMAIL_BODY = '\n'.join(['You previously participated in the study "Economic Decision-Making" on Mechanical Turk. You are invited to participate in a follow-up HIT. The task will be similar, but less than half as long as the first HIT, so the reward is now $0.50 rather than $1.00. Here is the HIT:',
    '',
    'https://www.mturk.com/mturk/preview?groupId=22S6R70G5R98HHWI0FYWZSTNYLRQAN'])

def f():
    parser = argparse.ArgumentParser()
    parser.add_argument('JSON_PATH',
        help = 'path to data file')
    parser.add_argument('N', type = int,
        help = 'number of new workers to admit')
    args = parser.parse_args()
    return (args.JSON_PATH, args.N)
json_path, number_to_admit = f()

with open(json_path, 'r') as o:
   data = json.load(o)
def save():
    with open(json_path, 'w') as o:
        json.dump(data, o, sort_keys = True, indent = 2)
def timestamp():
    return time.strftime("%Y-%m-%d %H:%M:%S %z")

con = boto.mturk.connection.MTurkConnection(host =
    'mechanicalturk.amazonaws.com' if data.get('production') else 'mechanicalturk.sandbox.amazonaws.com')

# Admit up to 'number_to_admit' new workers by granting them
# the necessary qualification.
admitted = 0
for w in data['workers']:
    if admitted == number_to_admit:
        break
    if not w['qualified']:
        con.assign_qualification(
            data['qualification']['id'],
            w['id'],
            data['qualification']['value'],
            send_notification = False)
              # Instead of using the standard qualification
              # notification, we'll send our own message to newly
              # qualified workers with NotifyWorkers.
        w['qualified'] = timestamp()
        save()
        admitted += 1

# Notify of the new HIT all qualified workers who haven't already
# been notified.
to_notify = [w for w in data['workers'] if
    w['qualified'] and not w['notified']]
con.notify_workers([w['id'] for w in to_notify],
    EMAIL_SUBJECT, EMAIL_BODY)
now = timestamp()
for w in to_notify:
    w['notified'] = now
save()
