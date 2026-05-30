import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, MoreThanOrEqual, LessThanOrEqual } from 'typeorm';
import { ReminderEntity } from './entities/reminder.entity';
import { CreateReminderDto } from './dto/create-reminder.dto';
import { UpdateReminderDto } from './dto/update-reminder.dto';

export interface ReminderResponse {
  id: number;
  userId: number;
  text: string;
  scheduledAt: Date;
  isRecurring: boolean;
  weekdays: number[] | null;
  createdAt: Date;
  updatedAt: Date;
}

@Injectable()
export class RemindersService {
  constructor(
    @InjectRepository(ReminderEntity)
    private readonly remindersRepo: Repository<ReminderEntity>,
  ) {}

  /** Map entity to response DTO */
  private toResponse(entity: ReminderEntity): ReminderResponse {
    return {
      id: entity.id,
      userId: entity.userId,
      text: entity.text,
      scheduledAt: entity.scheduledAt,
      isRecurring: entity.isRecurring,
      weekdays: entity.weekdays,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    };
  }

  async findAll(userId: number, showPast = false): Promise<ReminderResponse[]> {
    const now = new Date();

    if (showPast) {
      // Return all reminders for user (past + future)
      const reminders = await this.remindersRepo.find({
        where: { userId },
        order: { scheduledAt: 'DESC' },
      });
      return reminders.map(this.toResponse);
    }

    // Future reminders only (scheduledAt >= now)
    // For recurring reminders we always show them (they repeat)
    const upcomingNonRecurring = await this.remindersRepo.find({
      where: [
        {
          userId,
          isRecurring: false,
          scheduledAt: MoreThanOrEqual(now),
        },
      ],
      order: { scheduledAt: 'ASC' },
    });

    const recurring = await this.remindersRepo.find({
      where: [
        {
          userId,
          isRecurring: true,
        },
      ],
      order: { createdAt: 'DESC' },
    });

    // Combine: recurring first (sorted by creation), then upcoming non-recurring
    const result = [
      ...recurring.map(this.toResponse),
      ...upcomingNonRecurring.map(this.toResponse),
    ];

    return result;
  }

  async findOne(userId: number, id: number): Promise<ReminderResponse | null> {
    const reminder = await this.remindersRepo.findOne({
      where: { userId, id },
    });
    if (!reminder) return null;
    return this.toResponse(reminder);
  }

  async create(userId: number, dto: CreateReminderDto): Promise<ReminderResponse> {
    const reminder = this.remindersRepo.create({
      userId,
      text: dto.text,
      scheduledAt: dto.scheduledAt,
      isRecurring: dto.isRecurring ?? false,
      weekdays: dto.isRecurring && dto.weekdays ? dto.weekdays : null,
    });
    await this.remindersRepo.save(reminder);
    return this.toResponse(reminder);
  }

  async update(userId: number, id: number, dto: UpdateReminderDto): Promise<ReminderResponse> {
    const reminder = await this.remindersRepo.findOne({
      where: { userId, id },
    });
    if (!reminder) {
      throw new NotFoundException(`Напоминание #${id} не найдено`);
    }

    if (dto.text !== undefined) reminder.text = dto.text;
    if (dto.scheduledAt !== undefined) reminder.scheduledAt = dto.scheduledAt;
    if (dto.isRecurring !== undefined) reminder.isRecurring = dto.isRecurring;
    if (dto.weekdays !== undefined) {
      reminder.weekdays = reminder.isRecurring ? dto.weekdays : null;
    }

    await this.remindersRepo.save(reminder);
    return this.toResponse(reminder);
  }

  async remove(userId: number, id: number): Promise<void> {
    const result = await this.remindersRepo.delete({ userId, id });
    if (result.affected === 0) {
      throw new NotFoundException(`Напоминание #${id} не найдено`);
    }
  }
}
