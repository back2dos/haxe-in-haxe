package unit;

import core.ds.PriorityQueue.PriorityQueues;

class PriorityQueueTest {
	public static function main():Void {
		var queue = PriorityQueues.empty();
		queue = PriorityQueues.insert(queue, 3, "third");
		queue = PriorityQueues.insert(queue, 1, "first");
		queue = PriorityQueues.insert(queue, 2, "second");
		var ordered:Array<String> = [];
		while (!PriorityQueues.isEmpty(queue)) {
			var extracted = PriorityQueues.extract(queue);
			ordered.push('${extracted.priority}:${extracted.element}');
			queue = extracted.queue;
		}
		if (ordered.join(",") != "1:first,2:second,3:third") throw "Priority extraction order failed";

		var first = PriorityQueues.insert(PriorityQueues.empty(), 2, "two");
		var second = PriorityQueues.insert(PriorityQueues.empty(), 1, "one");
		if (PriorityQueues.extract(PriorityQueues.merge(first, second)).element != "one") throw "Priority merge failed";
	}
}
