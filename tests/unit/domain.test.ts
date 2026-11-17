import {describe,it,expect} from 'vitest';
import {internalNext,aggregate,toUTC,weekRange,overlaps,httpsURL,sanitizeFilename} from '../../src/lib/domain';
import {comparisonRanges} from '../../src/lib/metrics';
import {parseCommand} from '../../src/lib/commands';
describe('safe redirects',()=>{
 it.each(['https://evil.test','//evil.test','/\\evil.test','/app?next=https://evil.test','/app%2f%2fexample.test','/app\nLocation: x','/api/command','/app#fragment'])('rejects %s',value=>expect(internalNext(value)).toBe('/app'));
 it.each(['/app/treinos','/app/scrims/abc','/redefinir-senha','/convite/'+'a'.repeat(64)])('accepts known internal path %s',value=>expect(internalNext(value)).toBe(value));
});
describe('measurable results',()=>{
 it('weights attempts instead of averaging percentages',()=>{const r=aggregate([{attempts:1,hits:1},{attempts:99,hits:49}]);expect(r.rate).toBe(50);expect(r.sample).toBe(2);});
 it('has no rate without attempts',()=>expect(aggregate([{attempts:null,hits:null},{attempts:0,hits:0}]).rate).toBeNull());
 it('rejects impossible hits',()=>expect(parseCommand('training.result',{session_id:'30000000-0000-4000-8000-000000000001',attempts:3,hits:4,actual_minutes:20,difficulty:'',notes:''})?.success).toBe(false));
});
describe('time zones and interval boundaries',()=>{
 it('handles local midnight across UTC day',()=>expect(toUTC('2026-11-17T23:30','America/Sao_Paulo')).toBe('2026-11-18T02:30:00.000Z'));
 it('starts the week on Monday in the selected zone',()=>expect(weekRange(new Date('2026-11-16T01:00:00Z'),'America/Sao_Paulo').start).toBe('2026-11-09T03:00:00.000Z'));
 it('allows adjacent intervals',()=>{expect(overlaps({start:0,end:10},{start:10,end:20})).toBe(false);expect(overlaps({start:0,end:10},{start:9,end:20})).toBe(true);});
 it('rejects nonexistent DST local time',()=>expect(()=>toUTC('2026-03-08T02:30','America/New_York')).toThrow('INVALID_DATE'));
 it('compares equivalent week windows',()=>{const r=comparisonRanges(new Date('2026-11-17T15:00:00Z'),'America/Sao_Paulo','week');expect(r.currentStart).toBe('2026-11-16T03:00:00.000Z');expect(r.previousStart).toBe('2026-11-09T03:00:00.000Z');expect(r.previousEnd).toBe('2026-11-10T15:00:00.000Z');});
 it('caps month comparisons to the shorter month',()=>{const r=comparisonRanges(new Date('2026-03-31T15:00:00Z'),'America/Sao_Paulo','month');expect(r.sampleDays).toBe(28);});
});
describe('files and links',()=>{
 it.each(['javascript:alert(1)','http://example.test','https://user:password@example.test'])('rejects unsafe link %s',v=>expect(httpsURL(v)).toBe(false));
 it('accepts an HTTPS reference',()=>expect(httpsURL('https://example.test/demo')).toBe(true));
 it('normalizes file names',()=>expect(sanitizeFilename('../secret\u0000.dem')).toBe('.._secret_.dem'));
});
