import { Router, Request, Response, NextFunction } from 'express';
import rateLimit from 'express-rate-limit';
import { getSubjects } from '../controllers/SubjectController.js';
import { startGame, submitAnswer, restartGame } from '../controllers/GameController.js';
import { createRoom, getRoomState, joinRoom, heartbeat } from '../controllers/RoomController.js';

const router = Router();

const roomCreationLimit = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  message: { error: 'Too many rooms created. Please try again later.' },
});

// Validates :code param is exactly 3 alphanumeric characters
function validateRoomCode(req: Request, res: Response, next: NextFunction): void {
  const code = String(req.params.code).toUpperCase();
  if (!/^[A-Z0-9]{3}$/.test(code)) {
    res.status(400).json({ error: 'Invalid room code format' });
    return;
  }
  next();
}

router.get('/subjects', getSubjects);
router.post('/rooms', roomCreationLimit, createRoom);
router.get('/rooms/:code', validateRoomCode, getRoomState);
router.post('/rooms/:code/join', validateRoomCode, joinRoom);
router.post('/rooms/:code/start', validateRoomCode, startGame);
router.post('/rooms/:code/answer', validateRoomCode, submitAnswer);
router.post('/rooms/:code/heartbeat', validateRoomCode, heartbeat);
router.post('/rooms/:code/restart', validateRoomCode, restartGame);

export default router;
