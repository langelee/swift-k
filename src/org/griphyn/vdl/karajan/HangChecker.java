/*
 * Copyright 2012 University of Chicago
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 * http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


package org.griphyn.vdl.karajan;

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.Timer;
import java.util.TimerTask;

import org.apache.log4j.Logger;
import org.globus.cog.karajan.scheduler.WeightedHostScoreScheduler;
import org.globus.cog.karajan.stack.VariableStack;
import org.globus.cog.karajan.workflow.ExecutionException;
import org.globus.cog.karajan.workflow.events.EventBus;
import org.globus.cog.karajan.workflow.nodes.grid.SchedulerNode;
import org.griphyn.vdl.mapping.DSHandle;

public class HangChecker extends TimerTask {
    public static final Logger logger = Logger.getLogger(HangChecker.class);
    
    public static final int CHECK_INTERVAL = 10000;
    private Timer timer;
    private long lastEventCount;
    private VariableStack stack;
    
    public HangChecker(VariableStack stack) throws ExecutionException {
        this.stack = stack;
    }

    public void start() {
        timer = new Timer("Hang checker");
        timer.scheduleAtFixedRate(this, CHECK_INTERVAL, CHECK_INTERVAL);
    }

    public void run() {
        try {
            WeightedHostScoreScheduler s = (WeightedHostScoreScheduler) stack.getGlobal(SchedulerNode.SCHEDULER);
            if (s != null) {
                int running = s.getRunning();
                boolean allOverloaded = s.allOverloaded();
                if (running == 0 && EventBus.eventCount == lastEventCount && !allOverloaded) {
                    logger.warn("No events in " + (CHECK_INTERVAL / 1000) + "s.");
                    ByteArrayOutputStream os = new ByteArrayOutputStream();
                    PrintStream ps = new PrintStream(os);
                    Monitor.dumpVariables(ps);
                    Monitor.dumpThreads(ps);
                    findCycles(ps);
                    logger.warn(os.toString());
                    ps.close();
                }
            }
            lastEventCount = EventBus.eventCount;
        }
        catch (Exception e) {
            logger.warn("Exception caught during hang check", e);
        }
    }
    
    private static void findCycles(PrintStream ps) {
    	Map<VariableStack, DSHandle> wt = WaitingThreadsMonitor.getAllThreads();
        Map<VariableStack, List<DSHandle>> ot = WaitingThreadsMonitor.getOutputs();
        Map<DSHandle, List<VariableStack>> rwt = new HashMap<DSHandle, List<VariableStack>>();
        
        for (Map.Entry<VariableStack, DSHandle> e : wt.entrySet()) {
            List<VariableStack> l = rwt.get(e.getValue());
            if (l == null) {
                l = new LinkedList<VariableStack>();
                rwt.put(e.getValue(), l);
            }
            l.add(e.getKey());
        }
        
        Set<VariableStack> seen = new HashSet<VariableStack>();
        LinkedList<Object> cycle = new LinkedList<Object>();
        List<LinkedList<Object>> cycles = new ArrayList<LinkedList<Object>>();
        for (VariableStack t : wt.keySet()) {
            seen.clear();
            cycle.clear();
            findLoop(t, rwt, ot, seen, cycle, cycles);
        }
        
        cycles = removeDuplicates(cycles);
        
        if (cycles.size() == 1) {
            ps.println("Dependency loop found:");
        }
        else if (cycles.size() > 1) {
        	ps.println(cycles.size() + " dependency loops found:");
        }
        int index = 0;
        for (LinkedList<Object> c : cycles) {
            index++;
            if (cycles.size() > 1) {
                ps.println("* " + index);
            }
            Object prev = c.getLast();
            for (Object o : c) {
                if (o instanceof VariableStack) {
                    ps.println("\t" + Monitor.varWithLine((DSHandle) prev) + " is needed by: ");
                    for (String t : Monitor.getSwiftTrace((VariableStack) o)) {
                    	ps.println("\t\t" + t);
                    }
                }
                else { 
                    prev = o;
                    ps.println("\tand produces " + Monitor.varWithLine((DSHandle) o));
                    ps.println();
                }
            }
        }
        if (cycles.size() > 0) {
        	ps.println("----");
        }
    }
    
    private static List<LinkedList<Object>> removeDuplicates(List<LinkedList<Object>> cycles) {
    	List<LinkedList<Object>> nc = new LinkedList<LinkedList<Object>>();
    	while (!cycles.isEmpty()) {
    		Iterator<LinkedList<Object>> i = cycles.iterator();
    		LinkedList<Object> first = i.next();
    		i.remove();
    		
    		while (i.hasNext()) {
    			if (isSameCycle(first, i.next())) {
    				i.remove();
    			}
    		}
    		nc.add(first);
    	}
    	return nc;
    }

    private static boolean isSameCycle(LinkedList<Object> a, LinkedList<Object> b) {
        if (a.size() != b.size()) {
        	return false;
        }
        Iterator<Object> i = a.iterator();
        Object o = i.next();
        Iterator<Object> j = b.iterator();
        while (j.hasNext()) {
        	if (o == j.next()) {
        		while (i.hasNext()) {
        		    if (!j.hasNext()) {
        		        j = b.iterator();
        		    }
        		    if (i.next() != j.next()) {
        		    	return false;
        		    }
        		}
        		return true;
        	}
        }
        return false;
    }

    private static void findLoop(VariableStack t, Map<DSHandle, List<VariableStack>> rwt,
            Map<VariableStack, List<DSHandle>> ot, Set<VariableStack> seen, LinkedList<Object> cycle, List<LinkedList<Object>> cycles) {
        if (t == null) {
            return;
        }
        if (seen.contains(t)) {
            cycles.add(new LinkedList<Object>(cycle));
            return;
        }
        cycle.add(t);
        seen.add(t);
        // follow all the outputs of t
        List<DSHandle> l = ot.get(t);
        if (l != null) {
            for (DSHandle h : l) {
                cycle.add(h);
                List<VariableStack> l2 = rwt.get(h);
                if (l2 != null) {
                    for (VariableStack t2 : l2) {
                        findLoop(t2, rwt, ot, seen, cycle, cycles);
                    }
                }
                cycle.removeLast();
            }
        }
        cycle.removeLast();
        seen.remove(t);
    }

}
