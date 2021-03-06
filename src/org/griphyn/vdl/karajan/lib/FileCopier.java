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


package org.griphyn.vdl.karajan.lib;

import java.io.File;

import k.rt.AbstractFuture;
import k.rt.Future;

import org.apache.log4j.Logger;
import org.globus.cog.abstraction.impl.common.StatusEvent;
import org.globus.cog.abstraction.impl.common.task.FileTransferSpecificationImpl;
import org.globus.cog.abstraction.impl.common.task.FileTransferTask;
import org.globus.cog.abstraction.impl.common.task.FileTransferTaskHandler;
import org.globus.cog.abstraction.impl.common.task.IllegalSpecException;
import org.globus.cog.abstraction.impl.common.task.InvalidSecurityContextException;
import org.globus.cog.abstraction.impl.common.task.InvalidServiceContactException;
import org.globus.cog.abstraction.impl.common.task.ServiceContactImpl;
import org.globus.cog.abstraction.impl.common.task.ServiceImpl;
import org.globus.cog.abstraction.impl.common.task.TaskSubmissionException;
import org.globus.cog.abstraction.interfaces.FileTransferSpecification;
import org.globus.cog.abstraction.interfaces.Service;
import org.globus.cog.abstraction.interfaces.Status;
import org.globus.cog.abstraction.interfaces.StatusListener;
import org.globus.cog.abstraction.interfaces.TaskHandler;
import org.globus.cog.karajan.futures.FutureEvaluationException;
import org.griphyn.vdl.mapping.AbsFile;
import org.griphyn.vdl.mapping.PhysicalFormat;
import org.griphyn.vdl.mapping.file.SymLinker;

public class FileCopier extends AbstractFuture implements Future, StatusListener {
    private static final Logger logger = Logger.getLogger(FileCopier.class);
    
    private static final boolean canLink = SymLinker.canSymLink();
    private static final TaskHandler fth = new FileTransferTaskHandler();

    private AbsFile fsrc, fdst;
    private FileTransferTask task;
    private Exception exception;
    private boolean closed, destIsTemporary;
    private static int running;

    public FileCopier(PhysicalFormat src, PhysicalFormat dst, boolean destIsTemporary) {
        fsrc = (AbsFile) src;
        fdst = (AbsFile) dst;
        this.destIsTemporary = destIsTemporary;
    }

    public void fail(FutureEvaluationException e) {
        this.exception = e;
        notifyListeners();
    }

    public Object getValue() {
        return null;
    }

    public boolean isClosed() {
        return closed;
    }

    public boolean start() throws IllegalSpecException,
            InvalidSecurityContextException, InvalidServiceContactException,
            TaskSubmissionException {
        if (!destIsTemporary || !tryLink(fsrc, fdst)) {
            FileTransferSpecification fts = new FileTransferSpecificationImpl();
            fts.setDestinationDirectory(fdst.getDirectory());
            fts.setDestinationFile(fdst.getName());
            fts.setSourceDirectory(fsrc.getDirectory());
            fts.setSourceFile(fsrc.getName());
            fts.setThirdPartyIfPossible(true);
            task = new FileTransferTask();
            task.setSpecification(fts);
            task.setService(Service.FILE_TRANSFER_SOURCE_SERVICE, new ServiceImpl(
                fsrc.getProtocol("file"), new ServiceContactImpl(fsrc.getHost("localhost")), null));
            task.setService(Service.FILE_TRANSFER_DESTINATION_SERVICE,
                new ServiceImpl(fdst.getProtocol("file"), new ServiceContactImpl(fdst
                    .getHost("localhost")), null));
            task.addStatusListener(this);
            synchronized(FileCopier.class) {
                running++;
            }
            fth.submit(task);
            return false;
        }
        else {
            return true;
        }
    }

    private boolean tryLink(AbsFile fsrc, AbsFile fdst) {
        if (!canLink) {
            return false;
        }
        if (!isLocal(fsrc) || !isLocal(fdst)) {
            return false;
        }
        try {
            // delete destination; the behavior of a file copy would be 
            // destructive, and we want that
            String dstPath = fdst.getAbsolutePath();
            new File(dstPath).delete();
            String srcPath = fsrc.getAbsolutePath();
            if (logger.isDebugEnabled()) {
                logger.debug("LINK src=" + srcPath + " dst=" + dstPath);
            }
            SymLinker.symLink(srcPath, dstPath);
            return true;
        }
        catch (Exception e) {
            return false;
        }
    }

    private boolean isLocal(AbsFile f) {
        return "file".equals(f.getProtocol("file"));
    }

    public void close() {
        closed = true;
        notifyListeners();
    }
    
    public static int getRunning() {
        return running;
    }

    public void statusChanged(StatusEvent event) {
        Status s = event.getStatus();
        if (s.isTerminal()) {
            synchronized(FileCopier.class) {
                running--;
            }
            if (s.getStatusCode() == Status.COMPLETED) {
                close();
            }
            else {
                this.exception = new Exception(s.getMessage(), s.getException());
                close();
            }
        }
    }
    
    public Exception getException() {
        return exception;
    }
}
