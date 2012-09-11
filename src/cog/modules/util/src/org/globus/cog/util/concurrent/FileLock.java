//----------------------------------------------------------------------
//This code is developed as part of the Java CoG Kit project
//The terms of the license can be found at http://www.cogkit.org/license
//This message may not be removed or altered.
//----------------------------------------------------------------------

/*
 * Created on Aug 5, 2012
 */
package org.globus.cog.util.concurrent;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileFilter;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.security.SecureRandom;
import java.util.Random;

import org.apache.log4j.Logger;

/**
 * An implementation of file locks using Lamport's Bakery algorithm.
 * It tries to use the PID as thread identifier with fallback to random numbers.
 *
 * The Entering and Number arrays are implemented as sparse arrays of
 * files in some directory.
 */
public class FileLock {    
    public static final Logger logger = Logger.getLogger(FileLock.class);
    
    public static final String NUMBER = "locking.number";
    public static final String ENTERING = "locking.entering";
    
    private int myId, myN;
    private File dir;
    
    public FileLock(String dir) {
        this(new File(dir));
    }
    
    public FileLock(File dir) {
        this.dir = dir;
        dir.mkdirs();
        this.myId = getId();
    }

    private int getId() {
        try {
            return Integer.parseInt(new File("/proc/self").getCanonicalFile().getName());
        }
        catch (Exception e) {
            logger.warn("Failed to get PID of current process", e);
            try {
                SecureRandom rnd = SecureRandom.getInstance("SHA1PRNG");
                return rnd.nextInt() & 0x7fffffff;
            }
            catch (Exception ee) {
                logger.warn("Failed to get instance of SHA1PRNG", ee);
                return new Random().nextInt() & 0x7fffffff;
            }
        }
    }
    
    public void lock() throws IOException, InterruptedException {
        write(ENTERING, myId, 1);
        write(NUMBER, myId, myN = 1 + maxNumber());
        write(ENTERING, myId, 0);
        waitOther();
    }
    
    private void waitOther() throws InterruptedException {
        int last = -1;
        while (true) {
            int minIndex = getMinIndex(last);
            
            if (minIndex == Integer.MAX_VALUE) {
                // all remaining NUMBER[j] and ENTERING[j] are 0
                break;
            }
            File e = makeFile(ENTERING, minIndex);
            
            while (e.exists()) {
                Thread.sleep(100);
            }
            
            File n = makeFile(NUMBER, minIndex);
            
            while (n.exists()) {
                int nj = read(n);
                if (nj > myN || ((nj == myN) && (minIndex >= myId))) {
                    break;
                }
                Thread.sleep(100);
            }
            last = minIndex;
        }
    }

    private File makeFile(String prefix, int index) {
        return new File(dir, prefix + "." + index);
    }

    private int getMinIndex(final int greaterThan) {
        File[] numbers = dir.listFiles(new FileFilter() {
            @Override
            public boolean accept(File f) {
                String name = f.getName();
                return f.isFile() && (name.startsWith(NUMBER) || name.startsWith(ENTERING)) && (getIndex(f) > greaterThan);
            }
        });
        int min = Integer.MAX_VALUE;
        for (File n : numbers) {
            int in = getIndex(n);
            if (in < min) {
                min = in;
            }
        }
        return min;
    }

    private int getIndex(File n) {
        try {
            return Integer.parseInt(n.getName().substring(n.getName().lastIndexOf('.') + 1));
        }
        catch (Exception e) {
            throw new IllegalArgumentException("A file is conflicting with directory locking: " + n, e);
        }
    }

    private int maxNumber() {
        File[] numbers = dir.listFiles(new FileFilter() {
            @Override
            public boolean accept(File f) {
                return f.isFile() && f.getName().startsWith(NUMBER);
            }
        });
        
        int max = 0;
        for (File n : numbers) {
            int in = read(n);
            if (in > max) {
                max = in;
            }
        }
        return max;
    }

    private int read(File n) {
        try {
            BufferedReader br = new BufferedReader(new FileReader(n));
            try {
                return Integer.parseInt(br.readLine());
            }
            finally {
                br.close();
            }
        }
        catch (Exception e) {
            // nothing. The algorithm tolerates incorrect reads
        }
        return 0;
    }

    private void write(String prefix, int id, int value) throws IOException {
        File f = new File(dir, prefix + "." + id);
        if (value == 0) {
            if (!f.delete()) {
                f.deleteOnExit();
                throw new IOException("Failed to delete " + f);
            }
        }
        else {
            BufferedWriter br = new BufferedWriter(new FileWriter(f));
            try {
                br.write(String.valueOf(value));
            }
            finally {
                br.close();
            }
            f.deleteOnExit();
        }
    }

    public void unlock() throws IOException {
        write("locking.number", myId, 0);
    }
}