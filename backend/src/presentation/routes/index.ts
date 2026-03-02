import { Router, Request, Response, NextFunction } from 'express';
import rateLimit from 'express-rate-limit';
import { getSubjects } from '../controllers/SubjectController.js';
import { startGame, submitAnswer, restartGame, nextQuestion } from '../controllers/GameController.js';
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
// Async handler to wrap controller functions and catch unhandled promise rejections
const asyncHandler = (fn: (req: Request, res: Response, next: NextFunction) => Promise<void> | void) =>
  (req: Request, res: Response, next: NextFunction) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };

router.get('/subjects', asyncHandler(getSubjects));
router.post('/rooms', roomCreationLimit, asyncHandler(createRoom));
router.get('/rooms/:code', validateRoomCode, asyncHandler(getRoomState));
router.post('/rooms/:code/join', validateRoomCode, asyncHandler(joinRoom));
router.post('/rooms/:code/start', validateRoomCode, asyncHandler(startGame));
router.post('/rooms/:code/answer', validateRoomCode, asyncHandler(submitAnswer));
router.post('/rooms/:code/heartbeat', validateRoomCode, asyncHandler(heartbeat));
router.post('/rooms/:code/restart', validateRoomCode, asyncHandler(restartGame));
router.post('/rooms/:code/next-question', validateRoomCode, asyncHandler(nextQuestion));

export default router;
