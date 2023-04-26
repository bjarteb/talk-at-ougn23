import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  insecureSkipTLSVerify: true,
  stages: [
    { duration: '15s', target: 100 },
    { duration: '30s', target: 100 },
    { duration: '15s', target: 0 },
  ],
};

export default function() {
  let res = http.get('https://play.rippel.no');
  check(res, { 'status was 200': r => r.status == 200 });
  sleep(1);
}
