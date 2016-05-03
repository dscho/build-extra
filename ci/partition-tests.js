#!/usr/bin/env node

var bucketCount = 5;

if (process.argv.length > 2)
	bucketCount = parseInt(process.argv[2]);

if (bucketCount < 2) {
	console.log('-');
	process.exit(0);
}

var text = '';
var tests = [];
var regex = /^\[\d\d:\d\d:\d\d\] t(\d\d\d\d)-.* (\d+) ms( \(.*CPU\))?\n?$/;

var processText = function(text) {
	text.split("\n").map(function(line) {
		var match = line.match(regex);
		if (match) {
			no = parseInt(match[1], 10);
			ms = parseInt(match[2]);
			tests.push({ ms: ms, no: no, ms0: ms });
		}
	});

	if (bucketCount > tests.length) {
		console.log('Too many buckets (' + bucketCount + ') for '
			+ tests.length + ' tests!');
		process.exit(1);
	}

	tests.sort(function(a, b) {
		return a.no - b.no;
	});

	for (var i = 1; i < tests.length; i++)
		tests[i].ms += tests[i - 1].ms;

	var buckets = new Array(bucketCount + 1);
	buckets[0] = { to: '', ms: 0 };
	buckets[bucketCount] = { to: '', ms: tests[tests.length - 1].ms };
	var partition = function(left, i, right, j) {
		var middle = parseInt((left + right) / 2);
		var ms = (buckets[left].ms + buckets[right].ms)
			* (middle - left) / (right - left);
		var k = parseInt((i + j) / 2);


		if (tests[k].ms > ms)
			while (k - i - 1 > middle - left && tests[k].ms - ms >
					 ms - tests[k - 1].ms)
				k--;
		else if (tests[k].ms < ms)
			while (j - k - 1 > right - middle && ms - tests[k].ms >
					tests[k + 1].ms - ms)
				k++;
		buckets[middle] = { to: tests[k + 1].no, ms: tests[k].ms };
		if (middle - left > 1)
			partition(left, i, middle, k);
		if (right - middle > 1)
			partition(middle, k, right, j);
	};
	partition(0, -1, bucketCount, tests.length - 1);

	for (var i = bucketCount; i > 0; i--) {
		buckets[i].range = buckets[i - 1].to + '-' + buckets[i].to;
		buckets[i].ms -= buckets[i - 1].ms;
	}

	buckets.sort(function(a, b) {
		return b.ms - a.ms;
	});
	console.log(buckets.map(function(e) { return e.range; }).join(' '));
};

process.stdin.setEncoding('utf8');
process.stdin.on('data', function(chunk) {
	text += chunk.toString('utf8');
}).on('end', function() {
	processText(text);
});
